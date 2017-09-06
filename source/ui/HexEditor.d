module HexEditor;
import gtk.Builder;
import std.format;
import gdk.Event;
import gtk.Widget;
import gtk.Window;
import std.exception;
import gtk.TextBuffer;
import FileStrings;
import FilePresenter;
import gtk.TextView;
import gtk.Box;
import gtk.HBox;
import FileView;
import FileProxy;
import gtk.MessageDialog;
import gtk.MenuItem;
import gtk.ImageMenuItem;
import gtk.FileChooserDialog;
import NothrowDialog;
import DataTypeManager;
import TranslatorPresenter;
import gtk.Grid;
import gtk.Entry;
import Selection;
import Command;
import CommandLog;
import gtk.ToolButton;
import gtk.Clipboard;
import gdk.Atom;
import std.conv;
import Conversion;
import std.file;

/**
* Proxy function for clipboard requests. Forwards to singleton instance.
*/
private extern (C) void clipboardRequestProxy(GtkClipboard* clipboard,
		const(char)* text, void* userData)
{
	editor().onClipboardTextReceive(clipboard, text, userData);
}

// Accessor for singleton instance.
HexEditor editor()
{
	return HexEditor.editor;
}

/**
	Main editor class
*/
class HexEditor
{
private:
	this()
	{
		this.typeManager = new DataTypeManager();
		typeManager.RegisterBasicTypes();

		this.commandLog = new CommandLog();

		Builder builder = new Builder();
		enforce(std.file.exists(GladeFiles.EditorWindowFile),
				format("%s does not exist", GladeFiles.EditorWindowFile));
		builder.addFromFile(GladeFiles.EditorWindowFile);

		gladeWin = cast(Window)builder.getObject("editorWindow");
		enforce(gladeWin, format("Could not load EditorWindow from file %s",
				GladeFiles.EditorWindowFile));

		hexViewBox = cast(HBox)builder.getObject("hexViewBox");
		enforce(hexViewBox, format("Could not find hexViewBox in file %s",
				GladeFiles.EditorWindowFile));

		translatorContainer = cast(Grid)builder.getObject("translatorContainer");
		enforce(hexViewBox, format("Could not find translatorContainer in file %s",
				GladeFiles.EditorWindowFile));

		toolbarBox = cast(Box)builder.getObject("toolbarBox");
		enforce(toolbarBox, format("Could not find toolbarBox in file %s",
				GladeFiles.EditorWindowFile));

		toolbuttonUndo = cast(ToolButton)builder.getObject("toolbutton_undo");
		enforce(toolbuttonUndo, format("Could not find toolbutton_undo in file %s",
				GladeFiles.EditorWindowFile));

		toolbuttonRedo = cast(ToolButton)builder.getObject("toolbutton_redo");
		enforce(toolbuttonRedo, format("Could not find toolbutton_redo in file %s",
				GladeFiles.EditorWindowFile));

		addCallbacks(builder);
		gladeWin.addOnDelete(&onClose);
		gladeWin.setTitle(WINDOW_TITLE);

		gladeWin.show();
		gladeWin.addEvents(GdkEventMask.SCROLL_MASK);
		clipboard = Clipboard.get(internStaticString("CLIPBOARD"));
	}

public:
	/**
	* Initialize parts of editor that may require an Editor instance to be present.
	*/
	void init()
	{
		if (didInit)
			return;
		didInit = true;

		fileView = new FileView();
		fileView.setOnMove(&onMove);
		fileView.setOnSelectionUpdate(&onSelection);
		hexViewBox.packStart(fileView, true, true, 0);
		fileView.show();
	}

	static HexEditor editor()
	{
		static HexEditor instance;
		if (!instance)
			instance = new HexEditor();

		return instance;
	}

	bool onClose(Event event, Widget widget)
	{
		askForSave();
		import gtk.Main;

		Main.quit();
		return true;
	}

	Window win()
	{
		return gladeWin;
	}

	void openFile(string fileName)
	{
		try
		{
			auto newFile = new FileProxy(fileName);

			if (currentFile)
				currentFile.destroy();
			currentFile = newFile;

			if (filePresenter)
				filePresenter.setFile(currentFile);
			else
				filePresenter = new FilePresenter(fileView, currentFile);

			if (translatorPresenter)
				translatorPresenter.setFile(currentFile);
			else
				translatorPresenter = new TranslatorPresenter(translatorContainer,
						currentFile, typeManager);

			translatorContainer.show();
			commandLog.clear();
			gladeWin.setTitle(format("%s - %s", WINDOW_TITLE, currentFile.name()));

			import core.memory;

			GC.collect();
		}
		catch (ErrnoException e)
		{
			showErrorDialog(gladeWin, e.msg);
		}
	}

	void onMove()
	{
		ulong position = fileView.getCurrentAddress();

		if (filePresenter)
			filePresenter.setPosition(position);

		updateTranslator();
	}

	/// Run editor command
	void runCommand(ICommand command)
	{
		command.run();
		commandLog.add(command);

		toolbuttonUndo.setSensitive(commandLog.canUndo());
		toolbuttonRedo.setSensitive(commandLog.canRedo());
	}

	/// Undo last editor operation
	void undo()
	{
		commandLog.undo();
		toolbuttonUndo.setSensitive(commandLog.canUndo());
		toolbuttonRedo.setSensitive(commandLog.canRedo());
	}

	/// Redo last editor operation
	void redo()
	{
		commandLog.redo();
		toolbuttonUndo.setSensitive(commandLog.canUndo());
		toolbuttonRedo.setSensitive(commandLog.canRedo());
	}

	void addToolbarWidget(Widget w)
	{
		w.setHalign(GtkAlign.END);
		w.setVexpand(false);
		toolbarBox.add(w);
	}

	void onClipboardTextReceive(GtkClipboard* clipboard, const(char)* text, void* userData)
	{
		if (!currentFile || !text)
			return;

		string clipboardStr = to!string(text);
		ubyte[] data;
		try
		{
			data = stringToData(clipboardStr);
		}
		catch (Exception e)
		{
			showErrorDialog(gladeWin, e.msg);
			return;
		}

		Selection selection = fileView.getSelection();
		import FileManip : FileChangeCommand;

		runCommand(new FileChangeCommand(selection.lower, data, currentFile));
	}

private:
	void onSelection(Selection selection)
	{
		this.selection = selection;
		updateTranslator();
	}

	void addMenuCallback(Builder builder, string objectName, void delegate(MenuItem) func)
	{
		auto item = cast(ImageMenuItem)builder.getObject(objectName);
		enforce(item, format("Could not find %s", objectName));
		item.addOnActivate(func);
	}

	void addToolbarCallback(Builder builder, string objectName, void delegate(ToolButton) func)
	{
		auto item = cast(ToolButton)builder.getObject(objectName);
		enforce(item);
		item.addOnClicked(func);
	}

	void addCallbacks(Builder builder)
	{
		addMenuCallback(builder, "menuItem_new", &onMenuFileNew);
		addMenuCallback(builder, "menuItem_open", &onMenuFileOpen);
		addMenuCallback(builder, "menuItem_save", &onMenuFileSave);
		addMenuCallback(builder, "menuItem_saveAs", &onMenuFileSaveAs);
		addMenuCallback(builder, "menuItem_quit", &onMenuQuit);
		addMenuCallback(builder, "menuItem_about", &onMenuAbout);
		addMenuCallback(builder, "menuItem_undo", &onMenuUndo);
		addMenuCallback(builder, "menuItem_redo", &onMenuRedo);
		addMenuCallback(builder, "menuItem_goto", &onMenuGoto);
		addMenuCallback(builder, "menuItem_copy", &onMenuCopy);
		addMenuCallback(builder, "menuItem_paste", &onMenuPaste);
		addMenuCallback(builder, "menuItem_searchReplace", &onMenuSearchReplace);

		addToolbarCallback(builder, "toolbutton_new", &onToolbarNew);
		addToolbarCallback(builder, "toolbutton_open", &onToolbarOpen);
		addToolbarCallback(builder, "toolbutton_save", &onToolbarSave);
		addToolbarCallback(builder, "toolbutton_undo", &onToolbarUndo);
		addToolbarCallback(builder, "toolbutton_redo", &onToolbarRedo);
	}

	void onMenuQuit(MenuItem)
	{
		askForSave();
		import gtk.Main;

		Main.quit();
	}

	void onMenuUndo(MenuItem)
	{
		undo();
	}

	void onToolbarUndo(ToolButton)
	{
		undo();
	}

	void onMenuRedo(MenuItem)
	{
		redo();
	}

	void onToolbarRedo(ToolButton)
	{
		redo();
	}

	void onMenuFileOpen(MenuItem menuItem)
	{
		startOpenFileDialog();
	}

	void onToolbarOpen(ToolButton)
	{
		startOpenFileDialog();
	}

	void onMenuCopy(MenuItem)
	{
		copyToClipboard();
	}

	void onMenuPaste(MenuItem)
	{
		pasteFromClipboard();
	}

	void onMenuSearchReplace(MenuItem)
	{
		if (!currentFile)
			return;

		import SearchReplaceDialog;

		SearchReplaceDialog dialog = new SearchReplaceDialog(filePresenter, gladeWin);
		dialog.show();
	}

	void copyToClipboard()
	{
		if (!currentFile)
			return;

		Selection selection = fileView.getSelection();
		const(ubyte)[] data = currentFile.read(selection.lower, cast(uint)selection.length);

		string str = dataToString(data);
		clipboard.setText(str, cast(int)str.length);
	}

	void pasteFromClipboard()
	{
		if (!currentFile)
			return;

		clipboard.requestText(&clipboardRequestProxy, null);
	}

	void startOpenFileDialog()
	{
		auto openDialog = new FileChooserDialog("Open file", gladeWin, GtkFileChooserAction.OPEN,
				["Cancel", "OK"], [GtkResponseType.CANCEL, GtkResponseType.ACCEPT]);
		scope (exit)
			openDialog.destroy();

		auto response = openDialog.run();

		if (response == GtkResponseType.ACCEPT)
		{
			string fileName = openDialog.getFilename();
			openFile(fileName);
		}
	}

	void onMenuFileSave(MenuItem menuItem)
	{
		if (currentFile)
			currentFile.saveFile();
	}

	void onToolbarSave(ToolButton)
	{
		if (currentFile)
			currentFile.saveFile();
	}

	void onMenuFileSaveAs(MenuItem menuItem)
	{
		try
		{
			if (currentFile)
			{
				auto fileDialog = new FileChooserDialog("Save file", gladeWin, GtkFileChooserAction.SAVE,
						["Cancel", "Save"], [GtkResponseType.CANCEL, GtkResponseType.ACCEPT]);
				scope (exit)
					fileDialog.destroy();
				auto response = fileDialog.run();

				if (response == GtkResponseType.ACCEPT)
				{
					string fileName = fileDialog.getFilename();
					currentFile.saveAs(fileName);
					gladeWin.setTitle(format("%s - %s", WINDOW_TITLE, currentFile.name()));
				}
			}
		}
		catch (Exception e)
		{
			import NothrowDialog;

			showErrorDialog(gladeWin, e.msg);
		}

	}

	void onToolbarNew(ToolButton)
	{
		startNewFileDialog();
	}

	void onMenuFileNew(MenuItem menuItem)
	{
		startNewFileDialog();
	}

	/**
	Start the process of creating a new file. Ask user to save current file then create empty file at user-selected location.
	*/
	void startNewFileDialog()
	{
		try
		{
			askForSave();

			auto fileSizeDialog = new MessageDialog(gladeWin, GtkDialogFlags.MODAL,
					MessageType.QUESTION, ButtonsType.OK, "Enter file size in bytes");
			scope (exit)
				fileSizeDialog.destroy();
			import gtk.VBox;

			VBox messageArea = fileSizeDialog.getMessageArea();
			Entry sizeEntry = new Entry("0");
			sizeEntry.setActivatesDefault(true);
			messageArea.add(sizeEntry);
			fileSizeDialog.setDefaultResponse(GtkResponseType.OK);
			sizeEntry.show();

			auto response = fileSizeDialog.run();
			if (response == GtkResponseType.OK)
			{
				ulong fileSize = 0;
				string entryText = sizeEntry.getText();
				if (entryText.formattedRead!"%d"(fileSize) != 1)
					return;

				enforce(fileSize > 0, "File size must be bigger than 0");

				// Ask for file location
				auto fileDialog = new FileChooserDialog("Save file", gladeWin, GtkFileChooserAction.SAVE,
						["Cancel", "Save"], [GtkResponseType.CANCEL, GtkResponseType.ACCEPT]);
				scope (exit)
					fileDialog.destroy();
				auto fileResponse = fileDialog.run();

				if (fileResponse == GtkResponseType.ACCEPT)
				{
					string fileName = fileDialog.getFilename();
					FileProxy.createEmpty(fileName, fileSize);
					openFile(fileName);
				}
			}

		}
		catch (FormatException e)
		{
			showErrorDialog(gladeWin, "File size must be a number bigger than 0");
		}
		catch (Exception e)
		{
			showErrorDialog(gladeWin, e.msg);
		}
	}

	void askForSave()
	{
		if (currentFile)
		{
			auto saveDialog = new MessageDialog(gladeWin, GtkDialogFlags.MODAL,
					MessageType.QUESTION, ButtonsType.YES_NO, "Save current file?");
			scope (exit)
				saveDialog.destroy();
			auto response = saveDialog.run();

			if (response == GtkResponseType.YES)
				currentFile.saveFile();
		}
	}

	void onMenuGoto(MenuItem)
	{
		if (!currentFile)
			return;

		auto dialog = new MessageDialog(gladeWin, GtkDialogFlags.MODAL,
				MessageType.QUESTION, ButtonsType.OK, "Enter byte position: (decimal)");
		scope (exit)
			dialog.destroy();
		import gtk.VBox;

		VBox messageArea = dialog.getMessageArea();
		Entry positionEntry = new Entry("0");
		positionEntry.setActivatesDefault(true);
		messageArea.add(positionEntry);
		dialog.setDefaultResponse(GtkResponseType.OK);
		positionEntry.show();

		auto response = dialog.run();
		if (response == GtkResponseType.OK)
		{
			ulong position = 0;
			string entryText = positionEntry.getText();
			try
			{
				enforce(entryText.formattedRead!"%d"(position) == 1);
			}
			catch (Exception e)
			{
				showErrorDialog(gladeWin, "Invalid position value");
				return;
			}

			if (position >= currentFile.size)
			{
				showErrorDialog(gladeWin, "Position outside range");
				return;
			}

			fileView.moveTo(position);
			fileView.select(position, position);
		}
	}

	void onMenuAbout(MenuItem)
	{
		auto aboutMsg = new MessageDialog(gladeWin, GtkDialogFlags.MODAL,
				MessageType.INFO, ButtonsType.CLOSE, "About Freehex");
		scope (exit)
			aboutMsg.destroy();
		aboutMsg.setMarkup("Freehex is a free HEX editor for Windows, macOS and Linux.");
		aboutMsg.run();
	}

	/// Update starting position of a data translator
	void updateTranslator()
	{
		if (translatorPresenter)
			translatorPresenter.setPosition(selection.lower);
	}

	bool didInit;

	Box toolbarBox;
	HBox hexViewBox;
	ToolButton toolbuttonUndo;
	ToolButton toolbuttonRedo;

	CommandLog commandLog;
	Selection selection;
	Window gladeWin;
	FileView fileView;
	FilePresenter filePresenter;
	Grid translatorContainer;
	TranslatorPresenter translatorPresenter;
	FileProxy currentFile;
	DataTypeManager typeManager;
	Clipboard clipboard;
	enum WINDOW_TITLE = "Freehex";
}
