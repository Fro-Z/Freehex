module HexPresenter;
import DataViewport;
import std.format;
import gdk.Event;
import gtk.Widget;
import gdk.Keysyms;
import Interfaces;
import std.algorithm.searching;
import gdk.Keymap;
import std.exception;

/**
* Provides data in a HEX bytes to be displayed in DataViewport
*/
class HexPresenter : IDataPresenter
{
	this(DataViewport view)
	{
		this.view = view;
		this.writer = writer;
		view.setPresenter(this);
		view.addOnKeyPress(&onKeyPress);
	}

	void setData(const ubyte[] data)
	{
		byteData = data;
		view.queueDraw();
	}

	override string getCellText(int cellIdx) const
	{
		if (cellIdx < 0 || cellIdx >= byteData.length)
			return " ";

		return format("%02X", byteData[cellIdx]);
	}

	void setWriter(ICursorWriter writer)
	{
		this.writer = writer;
		writer.addOnCursorMoved(&onCursorMoved);
	}

private:

	void onCursorMoved()
	{
		upperByte = false;
	}

	bool onKeyPress(Event event, Widget widget)
	{
		auto lowercase = Keymap.keyvalToLower(event.key.keyval);
		dchar character = cast(dchar)(Keymap.keyvalToUnicode(lowercase));

		if (allowedChars.canFind(character))
		{
			if (!writer)
				return false;

			ubyte value;
			auto tmpstr = [character];
			const items = formattedRead(tmpstr, "%x", &value);
			enforce(items == 1, "Could not convert character to byte code!");

			if (upperByte)
			{
				// Create upper byte from value at cursor
				ubyte currentValue = writer.readAtCursor();
				currentValue <<= 4;
				value += currentValue;
			}

			writer.writeAtCursor(value, upperByte);
			upperByte = !upperByte;

			return true;
		}

		return false;
	}

	const(ubyte)[] byteData;
	DataViewport view;
	ICursorWriter writer;
	bool upperByte = false;

	dchar[] allowedChars = [
		'0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'
	];
}
