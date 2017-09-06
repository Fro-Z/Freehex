module FileManip;
import Command;
import FileProxy;

/**
* Command to modify section of a file
*/
class FileChangeCommand : ICommand
{
	this(ulong position, const ubyte[] data, FileProxy file)
	{
		this.data = data.idup;
		this.position = position;
		this.file = file;
	}

	override void run()
	{
		originalData = file.read(position, cast(uint)data.length).dup;
		file.write(position, data);
	}

	override void undo()
	{
		file.write(position, originalData);
	}

private:
	immutable ubyte[] data;
	immutable ulong position;
	const(ubyte)[] originalData;
	FileProxy file;

}
