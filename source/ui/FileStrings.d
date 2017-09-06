module FileStrings;
import std.file;
import std.path;

/**
Locations of glade files. Location must be determined at runtime. macOS working directory does not match the executable directory.
*/
class GladeFiles
{
	static string EditorWindowFile() @property
	{
		return  dirName(thisExePath()) ~ dirSeparator ~ "glade/editorWindow.glade";
	}

	static string SearchReplaceDialogFile() @property
	{
		 return  dirName(thisExePath()) ~ dirSeparator ~ "glade/dialog_searchReplace.glade";
	}


};
