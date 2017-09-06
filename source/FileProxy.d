module FileProxy;
import std.exception;
import std.file;
import std.algorithm.comparison;
import gtk.MessageDialog;
import gtk.Window;
import NothrowDialog;
import std.format;
import std.array;
import std.algorithm.searching : canFind;
import std.algorithm.mutation : remove;
import Interfaces;
import std.stdio;

version (testFileProxy)
	enum FILE_PAGE_SIZE = 128;
else
	enum FILE_PAGE_SIZE = 4096 * 4;

/// Create empty file with specified size
void createEmpty(string fileName, ulong size)
{
	enforce(size > 0, "Cannot create file of empty size");

	File file = File(fileName, "wb+");
	ulong bytesWritten = 0;
	ubyte[4096] zeroBuffer;
	while (bytesWritten < size)
	{
		size_t bytesToWrite = min(cast(size_t)(size - bytesWritten), zeroBuffer.length);
		file.rawWrite(zeroBuffer[0 .. bytesToWrite]);
		bytesWritten += bytesToWrite;
	}

	assert(file.size == size);
}

/**
* Range structure used by algorithms traversing the whole file. Contets of @FileRange are invalidated by writing into the parent @FileProxy
*/
struct FileRange
{
	this(FileProxy file, ulong startPosition)
	{
		this.file = file;
		this.position = startPosition;
		this.size = file.size;
		currentPage = file.getPage(startPosition / FILE_PAGE_SIZE).data;
	}

	ulong length()
	{
		return size - position;
	}

	bool empty()
	{
		return length == 0;
	}

	ubyte front()
	{
		return currentPage[position % FILE_PAGE_SIZE];
	}

	void popFront()
	{
		ulong oldPage = position / FILE_PAGE_SIZE;
		position++;
		ulong newPage = position / FILE_PAGE_SIZE;

		//load new page if needed
		if (oldPage != newPage)
			currentPage = file.getPage(newPage).data;
	}

	FileRange save()
	{
		return FileRange(file, position);
	}

private:
	immutable ulong size;
	ulong position;
	FileProxy file;
	const(ubyte)[] currentPage;
}

/**
*	Proxy between files and the application. Allows file operations without loading the whole file into the memory.
*/
class FileProxy
{
public:
	this()
	{
		this.cache = new CacheSystem();
	}

	this(string fileName)
	{
		this.cache = new CacheSystem();
		openFile(fileName);
	}

	this(File file)
	{
		this.file = file;
		this._size = file.size();
		this.cache = new CacheSystem();
	}

	void openFile(string fileName)
	{
		closeFile();
		file.open(fileName, "rb+");
		this._size = file.size();
	}

	string name() const
	{
		return file.name;
	}

	/**
	* Read up to  maxBytes bytes from file.
	*/
	const(ubyte)[] read(ulong position, uint maxBytes) nothrow
	{
		if (!file.isOpen || maxBytes == 0 || position >= size)
			return [];

		if (isMultiPageRequest(position, maxBytes))
			return readToNewBuffer(position, maxBytes);
		else
			return linkToCache(position, maxBytes);

	}

	/**
	* Write data to file at position.
	*/
	void write(ulong startPosition, const(ubyte)[] data)
	{
		if (!file.isOpen || data.length == 0)
			return;

		ulong endPosition = startPosition + data.length;

		//clamp size
		if (endPosition > size)
		{
			endPosition = size;
			data = data[0 .. cast(size_t)(endPosition - startPosition)];
		}

		ulong position = startPosition;
		while (position < endPosition)
		{
			ulong pageNum = position / FILE_PAGE_SIZE;
			Page page = getPage(pageNum);

			size_t pagePos = cast(size_t)(position % FILE_PAGE_SIZE);
			size_t dataOffset = cast(size_t)(position - startPosition);
			position += writeSlice(data[dataOffset .. $], page.data[pagePos .. $]);
			page.modified = true;
		}

		notifyListeners();
	}

	/**
	* Close file and discard changes
	*/
	void closeFile()
	{
		try
		{
			file.close();
			destroy(cache);
			cache = new CacheSystem();
		}
		catch (ErrnoException e)
		{
			showErrorDialog(null, e.msg);
		}

	}

	void saveFile()
	{
		//save all modified cached pages to current file
		auto modifiedPages = cache.modified;
		foreach (const Page page; modifiedPages)
		{
			file.seek(page.pageNum * FILE_PAGE_SIZE);
			file.rawWrite(page.data);
		}
	}

	/// Save into another file
	void saveAs(string fileName)
	{
		// Copy to new file
		File newFile = File(fileName, "wb+");
		foreach (ubyte[] buffer; file.byChunk(4096))
			newFile.rawWrite(buffer);

		file = newFile;
		saveFile();
	}

	/**
	* Size of the file
	*/
	auto size() nothrow
	{
		return _size;
	}

	void registerUpdateListener(IFileUpdateListener listener)
	{
		updateListeners ~= listener;
	}

	void removeUpdateListener(IFileUpdateListener listener)
	{
		updateListeners = remove!(elem => elem is listener)(updateListeners);
	}

private:
	bool isMultiPageRequest(ulong position, uint maxBytes) nothrow
	{
		auto startPage = position / FILE_PAGE_SIZE;
		auto endPage = (position + maxBytes) / FILE_PAGE_SIZE;
		return startPage != endPage;
	}

	ubyte[] readToNewBuffer(ulong startPosition, uint maxBytes) nothrow
	{
		try
		{
			ubyte[] buffer = new ubyte[maxBytes];
			ulong endPosition = startPosition + maxBytes;

			//clamp size
			if (endPosition > size)
			{
				endPosition = size;
				buffer = buffer[0 .. cast(size_t)(endPosition - startPosition)];
			}

			ulong position = startPosition;
			while (position < endPosition)
			{
				ulong pageNum = position / FILE_PAGE_SIZE;
				const Page page = getPage(pageNum);

				size_t pagePos = cast(size_t)(position % FILE_PAGE_SIZE);
				size_t bufferPos = cast(size_t)(position - startPosition);
				position += writeSlice(page.data[pagePos .. $], buffer[bufferPos .. $]);
			}

			return buffer;
		}
		catch (Exception e)
		{
			showErrorDialog(null, e.msg);
			return [];
		}
	}

	ubyte[] linkToCache(ulong position, uint maxBytes) nothrow
	in
	{
		assert(maxBytes <= FILE_PAGE_SIZE);
		assert(position < size);
	}
	body
	{
		immutable requestedPage = position / FILE_PAGE_SIZE;
		immutable pageOffset = position % FILE_PAGE_SIZE;

		try
		{
			Page page = getPage(requestedPage);

			size_t lastByte = cast(size_t)(min(pageOffset + maxBytes, page.data.length));

			return page.data[pageOffset .. lastByte];
		}
		catch (Exception e)
		{
			showErrorDialog(null, e.msg);
			return [];
		}
	}

	/// Get page from cache. Load page if not loaded
	Page getPage(ulong pageNum)
	{
		if (!cache.pageExists(pageNum))
		{
			// Load from file
			ulong filePosition = pageNum * FILE_PAGE_SIZE;
			file.seek(filePosition);

			ubyte[] pageData = new ubyte[FILE_PAGE_SIZE];
			pageData = file.rawRead(pageData);
			cache.addPage(new Page(pageData, pageNum));
		}

		return cache.getPage(pageNum);
	}

	void notifyListeners()
	{
		foreach (IFileUpdateListener listener; updateListeners)
			listener.onFileUpdate();
	}

	/// Copy data from one slice to another, stopping when either runs out of elements
	static ulong writeSlice(const ubyte[] from, ubyte[] to)
	{
		size_t numBytes = min(from.length, to.length);
		to[0 .. numBytes][] = from[0 .. numBytes];
		return numBytes;
	}

private:
	CacheSystem cache;

	File file;
	ulong _size;
	IFileUpdateListener[] updateListeners;
}

/// Forward range of pages
private struct PageRange
{
	this(CacheSystem cache, const(ulong)[] pageNums)
	{
		this.cache = cache;
		this.pageNums = pageNums;
	}

	@property PageRange save()
	{
		return this;
	}

	bool empty() const
	{
		return pageNums.empty;
	}

	Page front()
	{
		return cache.getPage(pageNums.front);
	}

	void popFront()
	{
		pageNums.popFront();
	}

	CacheSystem cache;
	const(ulong)[] pageNums;
}

/**
* CacheSystem manages added pages and freezes unused modified pages to be restored when needed.
*/
private class CacheSystem
{
public:
	bool pageExists(ulong pageNum)
	{
		return (pageNum in pageCache || pageNum in frozenPages);
	}

	~this()
	{
		destroy(frozenPages);
		destroy(pageCache);
	}

	/// Get range of modified pages
	@property PageRange modified()
	{
		ulong[] modifiedPages;

		foreach (const Page page; pageCache)
			if (page.modified)
				modifiedPages ~= page.pageNum;

		foreach (ulong pageNum, const ref File f; frozenPages)
		{
			if (!canFind(modifiedPages, pageNum))
				modifiedPages ~= pageNum;
		}

		return PageRange(this, modifiedPages);
	}

	/// Get page from cache system. Load page if frozen.
	Page getPage(ulong pageNum)
	{
		enforce(pageExists(pageNum), "Page must be added to CacheSystem first");

		if (pageNum !in pageCache)
			unfreezePage(pageNum);

		return pageCache[pageNum];
	}

	/// Add page to cache system.
	void addPage(Page page)
	{
		if (pageCache.length > MAX_CACHED_PAGES)
			flushCache();

		pageCache[page.pageNum] = page;
	}

	/// Has a page been ever modified
	bool isPageModified(ulong pageNum)
	{
		if (pageNum in frozenPages)
			return true;

		if (pageNum in pageCache)
			return pageCache[pageNum].modified;
		else
			return false;
	}

private:
	/// Freeze page to temporary file
	void freezePage(ulong pageNum)
	{
		enforce(pageNum in pageCache);

		Page page = pageCache[pageNum];

		if (pageNum !in frozenPages)
			frozenPages[pageNum] = File.tmpfile();

		File freezeFile = frozenPages[pageNum];

		freezeFile.seek(0);
		freezeFile.rawWrite(page.data);
	}

	/// Restore page from temporary file
	void unfreezePage(ulong pageNum)
	{
		enforce(pageNum in frozenPages);

		File f = frozenPages[pageNum];
		f.seek(0);
		immutable size_t fileSize = cast(size_t)f.size();
		ubyte[] pageData = new ubyte[fileSize];
		pageData = f.rawRead(pageData);
		pageCache[pageNum] = new Page(pageData, pageNum);
		pageCache[pageNum].modified = true;
	}

	/// Clear cached pages
	void flushCache()
	{
		foreach (ulong pageNum, Page page; pageCache)
		{
			// Save modified pages to file, discard the rest
			if (page.modified)
				freezePage(pageNum);
		}
		pageCache.clear();
	}

	Page[ulong] pageCache;
	File[ulong] frozenPages;
	enum MAX_CACHED_PAGES = 10;
}

private class Page
{
	this(ubyte[] data, ulong pageNum)
	{
		this.data = data;
		this.pageNum = pageNum;
	}

	immutable ulong pageNum;
	ubyte[] data;
	bool modified = false;
}

unittest
{

	FileProxy fp_NoFile = new FileProxy();
	try
	{
		auto readBytes = fp_NoFile.read(0, FILE_PAGE_SIZE);
		assert(readBytes.length == 0,
				"Reading from FileProxy without a file should return an empty slice");
	}
	catch (Exception e)
	{
		assert(false, "Reading from FileProxy without a file should not throw exception");
	}

}

version (testFileProxy)
{
	enum PATTERN_START = 42;

	ubyte[] createTestData(ubyte delegate(ulong) patternFunc, ulong size)
	{
		ubyte[] data = new ubyte[size];
		for (ulong i = 0; i < size; i++)
		{
			data[i] = patternFunc(i);
		}
		return data;
	}

	/// Test basic read
	unittest
	{
		ubyte delegate(ulong) patternFunc = i => cast(ubyte)((PATTERN_START + i) % 63);
		ubyte[] rawData = createTestData(patternFunc, FILE_PAGE_SIZE);

		Page p = new Page(rawData.dup, 0);
		CacheSystem cache = new CacheSystem();
		cache.addPage(p);

		assert(cache.pageExists(0), "Added page should exist");
		assert(!cache.pageExists(1), "Missing page should not exist");

		Page restored = cache.getPage(0);
		assert(restored.data == rawData, "Data should not change while in cache");
	}

	/// Test freeze unfreeze
	unittest
	{
		ubyte delegate(ulong) patternFunc = i => cast(ubyte)((PATTERN_START + i) % 63);
		ubyte[] rawData = createTestData(patternFunc, FILE_PAGE_SIZE - 10);

		Page p = new Page(rawData.dup, 0);
		CacheSystem cache = new CacheSystem();
		cache.addPage(p);

		//test freeze cycle
		cache.getPage(0).modified = true;
		cache.freezePage(0);
		cache.pageCache.clear();
		Page restored;
		assertNotThrown!Exception(restored = cache.getPage(0)); //will unfreeze automatically
		assert(restored.data.length == rawData.length, "Page size should not change during freeze");
		assert(restored.data == rawData, "Data should not change during freeze");
	}

	unittest
	{
		File rawFile = File.tmpfile;

		ubyte delegate(ulong) patternFunc = i => cast(ubyte)((PATTERN_START + i) % 63);
		ubyte delegate(ulong) alternativePatternFunc = i => cast(ubyte)(
				(PATTERN_START + 2 * i + 1) % 191);

		ubyte[] rawData = createTestData(patternFunc,
				FILE_PAGE_SIZE * CacheSystem.MAX_CACHED_PAGES * 2 + 10);

		rawFile.rawWrite(rawData);
		assert(rawFile.size == rawData.length);

		FileProxy proxy = new FileProxy(rawFile);
		assert(proxy.size == rawFile.size);

		const(ubyte)[] wholeRead = proxy.read(0, cast(uint)proxy.size);
		//Test read
		for (ulong i = 0; i < rawFile.size; i++)
		{
			const(ubyte)[] buff = proxy.read(i, 1);

			assert(buff.length > 0);
			assert(buff[0] == patternFunc(i),
					format("Proxy data does not match file data. Byte %s", i));
		}

		assert(proxy.read(proxy.size, 1).length == 0, "Should return empty slice on past-end read");

		//Test write
		ubyte[] alternativeData;
		for (ulong i = 0; i < rawFile.size; i++)
		{
			ubyte[] buff = [alternativePatternFunc(i)];
			alternativeData ~= alternativePatternFunc(i);
			proxy.write(i, buff);
		}

		//Check written data
		for (ulong i = 0; i < rawFile.size; i++)
		{
			const(ubyte)[] buff = proxy.read(i, 1);

			assert(buff.length > 0);
			assert(buff[0] == alternativePatternFunc(i),
					format("Proxy data does not match file data. Byte %s", i));
		}

		//Check written data as block
		const(ubyte)[] dataBlock = proxy.read(0, cast(uint)rawData.length);
		assert(dataBlock == alternativeData);

		//Test save
		proxy.saveFile();
		rawFile.seek(0);
		ubyte[] savedData = new ubyte[rawFile.size];
		savedData = rawFile.rawRead(savedData);
		assert(savedData == alternativeData);

	}

}
