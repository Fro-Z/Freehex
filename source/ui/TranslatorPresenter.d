module TranslatorPresenter;
import gtk.Container;
import FileProxy;
import DataTypeManager;
import DataType;
import DataDisplay;
import std.algorithm.comparison;
import std.system;
import Interfaces;
import gtk.CheckButton;
import gtk.Box;
import gtk.ToggleButton;
import gtk.Widget;
import FileManip;

/**
Presents binary file data as various data types in separate widgets.
*/
class TranslatorPresenter : IFileUpdateListener
{
	this(Container view, FileProxy file, DataTypeManager typeManager)
	{
		this.view = view;
		this.file = file;
		this.typeManager = typeManager;
		rebuildView();
		file.registerUpdateListener(this);
	}

	/// Set position in a file
	void setPosition(ulong position)
	{
		this.position = position;
		updateViewData();
	}

	/**
	* Rebuilds the widgets in provided view container
	*/
	void rebuildView()
	{
		typeDisplays = [];
		view.removeAll();
		bytesRequired = 0;

		addControls();

		const(DataType)[] types;
		if (isUnsigned)
			types = typeManager.getUnsignedTypes();
		else
			types = typeManager.getSignedTypes();

		foreach (const DataType type; types)
		{
			auto widget = type.createDisplayWidget();
			IDataDisplay dataDisp = cast(IDataDisplay)widget;
			typeDisplays ~= dataDisp;
			dataDisp.setPresenter(this);
			view.add(widget);
			bytesRequired = max(bytesRequired, type.size);
		}

		updateViewData();
		view.showAll();
	}

	/**
	* Set file to be used by Translator
	*/
	void setFile(FileProxy newFile)
	{
		this.file = newFile;
		file.registerUpdateListener(this);
		updateViewData();
	}

	/**
	* Called by child widgets as a request change to file data
	*/
	void onDataUpdate(const(ubyte)[] data)
	{
		import HexEditor;

		auto cmd = new FileChangeCommand(position, data, file);
		HexEditor.editor.runCommand(cmd);
	}

	//////// IFileUpdateListener interface: ////////

	override void onFileUpdate()
	{
		updateViewData();
	}

private:
	void updateViewData()
	{
		dataBuffer = file.read(position, bytesRequired);
		foreach (IDataDisplay display; typeDisplays)
			display.setData(dataBuffer, endian);
	}

	/// Add control checkboxes to view
	void addControls()
	{
		auto checkboxSign = new CheckButton("Unsigned");
		checkboxSign.setActive(isUnsigned);

		auto checkboxBigEndian = new CheckButton("Big endian");
		checkboxBigEndian.setActive(endian == Endian.bigEndian);

		auto checkboxBox = new Box(GtkOrientation.HORIZONTAL, 0);
		checkboxBox.packStart(checkboxSign, true, true, 0);
		checkboxBox.packStart(checkboxBigEndian, true, true, 0);

		checkboxSign.addOnToggled(&onChangeSign);
		checkboxBigEndian.addOnToggled(&onChangeEndian);

		view.add(checkboxBox);
	}

	void onChangeSign(ToggleButton btn)
	{
		isUnsigned = btn.getActive();
		rebuildView();
	}

	void onChangeEndian(ToggleButton btn)
	{
		endian = btn.getActive() ? Endian.bigEndian : Endian.littleEndian;
		updateViewData();
	}

	ulong position;
	bool isUnsigned;
	Endian endian = Endian.littleEndian;
	Container view;
	FileProxy file;
	DataTypeManager typeManager;
	IDataDisplay[] typeDisplays;

	uint bytesRequired;
	const(ubyte)[] dataBuffer;
}
