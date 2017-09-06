module Command;

/**
 Abstract interface for commands runnable by editor. Commands are logged by editor and can be undone.
*/
interface ICommand
{
	abstract void run();
	abstract void undo();
}
