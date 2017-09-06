module BasicTypeBox;
import gtk.Box;
import DataDisplay;
import gtk.Entry;
import DataType;
import gtk.Label;
import gtk.Separator;
import std.system;
import TranslatorPresenter;
import gtk.EditableIF;
import gdk.Event;
import gtk.Widget;

/**
* Widget designed to display data type with GTK Widget. This widget keeps only valid string in Entry. Data is written when focus leaves the Entry.
*/
class BasicTypeBox : Box, IDataDisplay
{
	this(const DataType type)
	{
		super(GtkOrientation.VERTICAL, 0);
		this.type = type;

		auto separator = new Separator(GtkOrientation.HORIZONTAL);
		packStart(separator, false, false, 0);

		auto label = new Label(type.name);
		packStart(label, false, false, SPACING);

		entry = new Entry();
		entry.setEditable(true);
		entry.addOnChanged(&onChanged);
		entry.addOnFocusOut(&onFocusOut);
		entry.addOnActivate(&onActivate);
		packStart(entry, true, true, 0);
	}

	override void setData(const ubyte[] data, Endian endian)
	{
		import std.algorithm.comparison : min;

		currentEndian = endian;
		immutable sliceSize = min(data.length, type.size);
		lastData = data.dup[0 .. sliceSize];
		lastText = type.fromData(data, endian);
		entry.setText(lastText);

	}

	void setPresenter(TranslatorPresenter presenter)
	{
		this.presenter = presenter;
	}

private:
	void onChanged(EditableIF editable)
	{
		// Do not trigger when cell is empty. (Empty event called when content is overwritten)
		string content = editable.getChars(0, -1);
		if (content.length == 0)
			return;

		// Allow signed types to begin with "-"
		if (content.length == 1 && content[0] == '-')
			return;

		try
		{
			ubyte[] data = type.fromString(content, currentEndian);
			lastText = content; //update last text when its valid
		}
		catch (InvalidStringException e)
		{
			editable.deleteText(0, -1);
			int pos = 0;

			if (content == lastText) //Failed with text that was good before
				lastText = ""; //This should not happen, but for some reason on Linux only it does

			editable.insertText(lastText, cast(int)lastText.length, pos);
		}
	}

	/**
	* Try to update presenter data. If data is invalid revert to last good data.
	*/
	void updatePresenterData()
	{
		try
		{
			ubyte[] data = type.fromString(entry.getChars(0, -1), currentEndian);
			if (data != lastData)
				presenter.onDataUpdate(data);
		}
		catch (InvalidStringException e)
			setData(lastData, currentEndian);
	}

	bool onFocusOut(Event, Widget)
	{
		// !!! Do not update data from focusEvent !!!
		// By the time the event is called the entry has new data inside!
		return false;
	}

	void onActivate(Entry)
	{
		updatePresenterData();
	}

private:
	string lastText;
	Entry entry;
	const(ubyte)[] lastData;
	TranslatorPresenter presenter;
	Endian currentEndian;
	const DataType type;
	enum SPACING = 5;
}
