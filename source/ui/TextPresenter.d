module TextPresenter;
import DataViewport;
import std.conv;
import std.utf;
import std.typecons;
import std.array;
import Interfaces;
import gdk.Event;
import gtk.Widget;
import gdk.Keymap;
import gtk.ComboBoxText;

enum TextMode
{
	/// Text is editable only in ASCII mode
	TEXT_ASCII = "ASCII",
	TEXT_UTF8 = "UTF-8"
}

/**
* Provides data as characters to be displayed in DataViewport.
* For Code points that span multiple bytes the character is displayed at the first byte's position.
* Rest of the characters are displayed as FILL_CHAR.
*/
class TextPresenter : IDataPresenter
{
	this(IDataViewport view)
	{
		this.view = view;
		view.setCellWidthScale(0.5f);
		view.setPresenter(this);
		view.addOnKeyPressProxy(&onKeyPress);
	}

	override string getCellText(int cellIdx) const
	{
		if (cellIdx < 0 || cellIdx >= displayChars.length)
			return " ";

		auto displayChar = displayChars[cellIdx];
		return to!string([displayChar]);
	}

	void setMode(TextMode mode)
	{
		currentMode = mode;
		updateDisplayChars();
		view.redraw();
	}

	void setData(const ubyte[] data)
	{
		byteData = cast(const(char)[])data;
		updateDisplayChars();
		view.redraw();
	}

	void setWriter(ICursorWriter writer)
	{
		this.writer = writer;
	}

	Widget createEncodingChooser()
	{
		import std.traits : EnumMembers;

		auto chooser = new ComboBoxText(false);
		chooser.addOnChanged(&onEncodingChanged);
		foreach (int column, TextMode t; EnumMembers!TextMode)
			chooser.appendText(t);

		chooser.setActiveText(currentMode);
		return chooser;
	}

private:
	void onEncodingChanged(ComboBoxText chooser)
	{
		import NothrowDialog;

		try
		{
			TextMode mode = cast(TextMode)chooser.getActiveText();
			setMode(mode);
		}
		catch (Exception e)
		{
			showErrorDialog(null, "Invalid encoding selected");
		}
	}

	/// Update cached displayChars array based on current text mode.
	void updateDisplayChars()
	{
		displayChars.length = byteData.length;
		displayChars[] = FILL_CHAR;

		final switch (currentMode)
		{
		case TextMode.TEXT_ASCII:
			foreach (size_t i; 0 .. byteData.length)
				displayChars[i] = cast(dchar)byteData[i];
			break;

		case TextMode.TEXT_UTF8:
			size_t index;
			while (index < byteData.length)
			{
				auto firstBytePos = index;
				displayChars[firstBytePos] = decode!(Yes.useReplacementDchar, const(char)[])(byteData,
						index);

				// Advance index manually if decoding failed
				if (firstBytePos == index)
					index++;
			}
			break;
		}

	}

	bool onKeyPress(Event event, Widget)
	{
		if (currentMode != TextMode.TEXT_ASCII)
			return false;

		dchar character = cast(dchar)(Keymap.keyvalToUnicode(event.key.keyval));

		import std.ascii : isASCII;

		if (isASCII(character) && character != '\0')
		{
			if (!writer)
				return false;

			ubyte value = cast(ubyte)character;
			writer.writeAtCursor(value, true);
			return true;
		}

		return false;
	}

	ICursorWriter writer;
	IDataViewport view;
	const(char)[] byteData;
	dchar[] displayChars;
	TextMode currentMode = TextMode.TEXT_ASCII;

	/// Fill char is displayed for bytes that are not first byte of Unicode code point
	enum FILL_CHAR = ' ';
}

version (unittest)
{
	class Mock_IDataViewport : IDataViewport
	{
		override void setCellWidthScale(float scale)
		{
		}

		override void setPresenter(IDataPresenter presenter)
		{
		}

		override void redraw()
		{
		}

		override void addOnKeyPressProxy(bool delegate(Event, Widget))
		{
		}
	}
}

unittest  // Test ASCII
{
	auto view = new Mock_IDataViewport();
	TextPresenter tp = new TextPresenter(view);

	tp.setMode(TextMode.TEXT_ASCII);

	immutable ubyte[] sourceData = ['a', 'b', 'c', 'd'];
	immutable dchar[] expectedOut = ['a', 'b', 'c', 'd'];
	tp.setData(sourceData);

	foreach (uint i; 0 .. cast(uint)sourceData.length)
	{
		auto displayedChar = tp.getCellText(i)[0];
		assert(expectedOut[i] == displayedChar);
	}
}

unittest  // Test UTF8
{
	auto view = new Mock_IDataViewport();
	TextPresenter tp = new TextPresenter(view);

	tp.setMode(TextMode.TEXT_UTF8);

	immutable ubyte[] sourceData = ['a', 'b', 'c', 'd', 0xC5, 0x99];
	immutable dchar[] expectedOut = ['a', 'b', 'c', 'd', 'ř', TextPresenter.FILL_CHAR];
	tp.setData(sourceData);

	foreach (uint i; 0 .. cast(uint)sourceData.length)
	{
		auto displayedChar = to!dstring(tp.getCellText(i))[0];
		assert(expectedOut[i] == displayedChar);
	}
}
