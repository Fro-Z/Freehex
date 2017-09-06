module SearchReplaceDialog;
import FilePresenter;
import Conversion;
import gtk.Entry;
import gtk.Builder;
import gtk.Dialog;
import gtk.Button;
import gdk.Event;
import gtk.Widget;
import std.ascii;
import gtk.EditableIF;
import std.format;
import FileStrings;
import std.exception;
import std.conv;
import std.algorithm.searching : all;
import std.array;
import Selection;
import NothrowDialog;
import gtk.Window;
import std.file;

class SearchReplaceDialog
{
	this(FilePresenter presenter, Window parent)
	{
		this.presenter = presenter;

		Builder builder = new Builder();
		enforce(std.file.exists(GladeFiles.SearchReplaceDialogFile),
				format("%s does not exist", GladeFiles.SearchReplaceDialogFile));
		builder.addFromFile(GladeFiles.SearchReplaceDialogFile);

		dialog = cast(Dialog)builder.getObject("dialog_searchReplace");
		enforce(dialog, format("Could not load dialog from file %s",
				GladeFiles.SearchReplaceDialogFile));

		patternEntry = cast(Entry)builder.getObject("patternEntry");
		enforce(patternEntry, format("Could not load patternEntry from file %s",
				GladeFiles.SearchReplaceDialogFile));

		replacementEntry = cast(Entry)builder.getObject("replacementEntry");
		enforce(patternEntry, format("Could not load replacementEntry from file %s",
				GladeFiles.SearchReplaceDialogFile));

		btnSearch = cast(Button)builder.getObject("btnSearch");
		enforce(btnSearch, format("Could not load btnSearch from file %s",
				GladeFiles.SearchReplaceDialogFile));

		btnReplace = cast(Button)builder.getObject("btnReplace");
		enforce(btnReplace, format("Could not load btnReplace from file %s",
				GladeFiles.SearchReplaceDialogFile));

		btnCancel = cast(Button)builder.getObject("btnCancel");
		enforce(btnSearch, format("Could not load btnCancel from file %s",
				GladeFiles.SearchReplaceDialogFile));

		patternEntry.addOnChanged(&onPatternChanged);
		replacementEntry.addOnChanged(&onReplacementChanged);

		dialog.setParent(parent);
		win = parent;
		btnCancel.addOnPressed(&onCancel);
		btnSearch.addOnPressed(&onSearch);
		btnReplace.addOnPressed(&onReplace);
	}

	void show()
	{
		dialog.show();
	}

private:
	/**
	* Both patterns must be valid hex strings of the same lengths.
	*/
	bool canReplace()
	{
		try
		{
			string patternStr = patternEntry.getChars(0, -1);
			enforce(patternStr.length % 2 == 0, "Pattern string must be in whole bytes");

			string replacementStr = replacementEntry.getChars(0, -1);
			enforce(replacementStr.length % 2 == 0, "Replacement string must be in whole bytes");

			ubyte[] patternData = stringToData(patternStr);
			ubyte[] replacementData = stringToData(replacementStr);

			enforce(patternData.length > 0, "Cannot search for empty string");
			enforce(patternData.length == replacementData.length,
					"Pattern and replacement must be of the same length");
		}
		catch (Exception e)
		{
			return false;
		}
		return true;
	}

	bool canSearch()
	{
		try
		{
			string patternStr = patternEntry.getChars(0, -1);
			enforce(patternStr.length % 2 == 0, "Pattern string must be in whole bytes");
			ubyte[] patternData = stringToData(patternStr);
			enforce(patternData.length > 0, "Cannot search for empty string");
		}
		catch (Exception e)
		{
			return false;
		}
		return true;
	}

	void updateButtons()
	{
		btnReplace.setSensitive(canReplace());
		btnSearch.setSensitive(canSearch());
	}

	void onPatternChanged(EditableIF)
	{
		dstring str = to!dstring(patternEntry.getChars(0, -1));
		if (str.length == 0)
			return;

		int pos;
		if (all!"std.ascii.isASCII(a) && std.ascii.isHexDigit(a)"(str))
			lastPatternString = to!string(str);
		else
		{
			patternEntry.deleteText(0, -1);
			if (lastPatternString.length > 0)
				patternEntry.insertText(lastPatternString, cast(int)lastPatternString.length, pos);
		}

		updateButtons();
	}

	void onReplacementChanged(EditableIF)
	{
		dstring str = to!dstring(replacementEntry.getChars(0, -1));
		if (str.length == 0)
			return;

		int pos;
		if (all!"std.ascii.isASCII(a) && std.ascii.isHexDigit(a)"(str))
			lastReplacementString = to!string(str);
		else
		{
			replacementEntry.deleteText(0, -1);
			if (lastReplacementString.length > 0)
				replacementEntry.insertText(lastReplacementString,
						cast(int)lastReplacementString.length, pos);
		}

		updateButtons();
	}

	void onCancel(Button)
	{
		dialog.hide();
		dialog.destroy();
	}

	/**
	* Try searching for given pattern
	*/
	void onSearch(Button)
	{
		try
		{
			ubyte[] patternData = stringToData(patternEntry.getChars(0, -1));
			enforce(patternData.length > 0, "Cannot search for empty string");

			// Move to next byte so that we dont find the same pattern again
			if (presenter.testSelectionForPattern(patternData))
				presenter.advanceSelection();

			Selection matchPosition;
			bool result = presenter.searchForPattern(patternData, matchPosition, false);
			if (result)
				presenter.showSelection(matchPosition);
			else
				showMessage(win, "No match found");
		}
		catch (Exception e)
		{
			showErrorDialog(win, e.msg);
		}
	}

	/**
	* Replace the pattern if selected. Otherwise search for next occurence.
	*/
	void onReplace(Button)
	{
		try
		{
			ubyte[] patternData = stringToData(patternEntry.getChars(0, -1));
			ubyte[] replacementData = stringToData(replacementEntry.getChars(0, -1));
			enforce(patternData.length > 0, "Cannot search for empty string");
			enforce(patternData.length == replacementData.length,
					"Pattern and replacement must be of the same length");

			// Replace only if pattern match is currently selected
			if (presenter.testSelectionForPattern(patternData))
				presenter.writeAtCursor(replacementData);

			Selection matchPosition;
			bool result = presenter.searchForPattern(patternData, matchPosition, false);
			if (result)
				presenter.showSelection(matchPosition);
		}
		catch (Exception e)
		{
			showErrorDialog(win, e.msg);
		}
	}

	Window win;
	FilePresenter presenter;
	Entry patternEntry;
	string lastPatternString;
	Entry replacementEntry;
	string lastReplacementString;
	Button btnCancel;
	Button btnSearch;
	Button btnReplace;
	Dialog dialog;
}
