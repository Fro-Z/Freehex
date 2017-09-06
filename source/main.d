import gtk.Label;
import gtk.Main;
import HexEditor;
import NothrowDialog;
import std.exception;

version (Windows)
{
	import core.runtime;
	import core.sys.windows.windows;
	import std.string;

	/**
Windows required custom winMain to hide console window
*/
	extern (Windows) int WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance,
			LPSTR lpCmdLine, int nCmdShow)
	{
		int result;

		try
		{
			Runtime.initialize();
			result = myWinMain(hInstance, hPrevInstance, lpCmdLine, nCmdShow);
			Runtime.terminate();
		}
		catch (Throwable e)
		{
			result = 1;
		}

		return result;
	}

	int myWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow)
	{
		return mainImpl([]);
	}
}
else
{
	int main(string[] args)
	{
		return mainImpl(args);
	}
}

int mainImpl(string[] args)
{
	Main.init(args);

	try
	{
		HexEditor.editor.init();
		HexEditor.editor.win.showAll();
		Main.run();
	}
	catch (Exception e)
	{
		showErrorDialog(null, e.msg);
	}

	return 0;
}
