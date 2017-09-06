module Interfaces;

interface ICursorWriter
{
	/// Write to current cursor position
	abstract void writeAtCursor(ubyte, bool advanceCursor = true);

	/// Add delegate to be called when cursor moves
	abstract void addOnCursorMoved(void delegate() del);

	/// Read from current cursor position
	abstract ubyte readAtCursor();
}

interface IFileUpdateListener
{
	/// When listener is registered this function is called after any change to a file
	abstract void onFileUpdate();
}
