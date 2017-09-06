module NothrowDialog;
import gtk.MessageDialog;
import gtk.Window;

/**
* Tries to create MessageDialog. Supressess exceptions if any pop up.
*/
void showErrorDialog(Window parent, string message) nothrow
{
	try
	{
		auto dialog = new MessageDialog(parent, GtkDialogFlags.MODAL,
				GtkMessageType.ERROR, GtkButtonsType.OK, message);
		dialog.run();
		dialog.destroy();
	}
	catch (Exception e)
	{

	}
}

void showMessage(Window parent, string message) nothrow
{
	try
	{
		auto dialog = new MessageDialog(parent, GtkDialogFlags.MODAL,
				GtkMessageType.INFO, GtkButtonsType.OK, message);
		dialog.run();
		dialog.destroy();
	}
	catch (Exception e)
	{

	}
}
