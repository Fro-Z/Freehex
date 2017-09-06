module FilePresenter;

import FileView;
import std.random;
import FileProxy;
import gtk.Adjustment;
import Interfaces;
import gdk.Event;
import gtk.Widget;
import HexEditor;
import FileManip;
import Selection;

/**
Presents binary file data to a FileView. Facilitates interaction between various editor components and files.
(M-V-P)
*/
class FilePresenter : ICursorWriter, IFileUpdateListener
{
public:
	this(FileView fileView, FileProxy file)
	{
		this.fileView = fileView;
		this.file = file;
		file.registerUpdateListener(this);

		fileView.setViewportData(dataBuffer);
		fileView.setFileSize(file.size);
		fileView.setWriter(this);
		fileView.resetSelection();
		fileView.setOnMove(&onMove);
		fileView.moveTo(0);
		fileView.queueDraw();
	}

	~this()
	{
		fileView.setOnMove(null);
	}

	void setPosition(ulong position)
	{
		fileView.moveTo(position);
	}

	ulong getPosition() const
	{
		return position;
	}

	void onMove()
	{
		auto oldPos = position;

		position = fileView.getCurrentAddress();
		updateViewData();

		if (oldPos != position)
			foreach (void delegate() func; onCursorMoveDelegates)
				func();
	}

	void setFile(FileProxy newFile)
	{
		this.file = newFile;
		file.registerUpdateListener(this);

		fileView.setFileSize(file.size);
		fileView.moveTo(0);
		fileView.queueDraw();
	}

	/**
	* Search for pattern in a file. First match is returned in @patternPosition.
	* @param fromBeginning Start search from beginning of the file
	* @return true Match found
	* @return false No match
	*/
	bool searchForPattern(const(ubyte)[] pattern, out Selection patternPosition,
			bool fromBeginning = false)
	{
		import std.algorithm.searching;

		assert(pattern.length > 0);

		ulong startPos = 0;
		if (!fromBeginning)
		{
			// go from selection
			startPos = fileView.getSelection().lower;
		}

		auto result = find(FileRange(file, startPos), pattern);
		if (result.length > 0)
		{
			ulong pos = file.size - result.length;
			patternPosition.update(pos, pos + pattern.length - 1);
			return true;
		}
		else
			return false;
	}

	bool testSelectionForPattern(const(ubyte)[] pattern)
	{
		Selection selection = fileView.getSelection();
		const(ubyte)[] actualData = file.read(selection.lower, cast(uint)selection.length);
		return actualData == pattern;
	}

	/**
	* Highlight a selection and move FileView so that it can be seen.
	*/
	void showSelection(Selection selection)
	{
		fileView.moveTo(selection.lower);
		fileView.select(selection.lower, selection.upper);
	}

	void writeAtCursor(const(ubyte)[] data)
	{
		auto cmd = new FileChangeCommand(fileView.getSelection().lower, data, file);
		HexEditor.editor.runCommand(cmd);
	}

	void advanceSelection()
	{
		fileView.advanceSelection();
	}

	//////// ICursorWriter interface: ////////
	override void writeAtCursor(ubyte data, bool advanceCursor)
	{
		writeAtCursor([data]);
		if (advanceCursor)
			advanceSelection();
	}

	override ubyte readAtCursor()
	{
		ulong pos = fileView.getSelection().lower;
		auto data = file.read(pos, 1);

		if (data.length > 0)
			return data[0];
		else
			return 0;
	}

	override void addOnCursorMoved(void delegate() del)
	{
		onCursorMoveDelegates ~= del;
	}

	//////// IFileUpdateListener interface: ////////

	override void onFileUpdate()
	{
		updateViewData();
	}

private:
	void updateViewData()
	{
		dataBuffer = file.read(position, fileView.bytesRequired);
		fileView.setViewportData(dataBuffer);
	}

	ulong position;
	const(ubyte)[] dataBuffer;
	void delegate()[] onCursorMoveDelegates;

	FileView fileView;
	FileProxy file;
}
