module CommandLog;
import Command;

/**
* Provides basic undo-redo system for commands. Commands added to CommandLog
* are fully owned by the instance and are destroyed upon their invalidation.
*/
class CommandLog
{
	/// Takes ownership of a command without running.
	/// Commands that are no longer undoable are destroyed.
	void add(ICommand command)
	{
		if (next != log.length)
		{
			log = log[0 .. next];

			foreach (ICommand cmd; log[next .. $])
				destroy(cmd);
		}

		log ~= command;
		next++;
	}

	/// Undo last command in command log if possible
	void undo()
	{
		if (canUndo())
		{
			log[next - 1].undo();
			next--;
		}
	}

	/// Redo last undo command in command log if possible
	void redo()
	{
		if (canRedo)
		{
			log[next].run();
			next++;
		}
	}

	bool canUndo() const
	{
		return next > 0;
	}

	bool canRedo() const
	{
		return next < log.length;
	}

	void clear()
	{
		log = [];
		next = 0;
	}

private:
	ICommand[] log;
	size_t next;
}

version (unittest)
{
	class TestCommand : ICommand
	{
		this(void delegate() doCmd, void delegate() undoCmd)
		{
			this.doCmd = doCmd;
			this.undoCmd = undoCmd;
		}

		override void run()
		{
			doCmd();
		}

		override void undo()
		{
			undoCmd();
		}

	private:
		void delegate() doCmd;
		void delegate() undoCmd;
	}
}

// Test basic undo redo
unittest
{
	int value;

	auto incrementOne = new TestCommand(() { value++; }, () { value--; });
	auto incrementTwo = new TestCommand(() { value += 2; }, () { value -= 2; });

	CommandLog cl = new CommandLog();

	incrementOne.run();
	cl.add(incrementOne);
	assert(value == 1, "Wrongly formed test command");

	assert(cl.canUndo(), "Cannot undo");

	cl.undo();
	assert(value == 0, "Command was not undone");

	assert(cl.canRedo(), "Cannot redo");

	cl.redo();
	assert(value == 1, "Command was not redone");

	incrementTwo.run();
	cl.add(incrementTwo);
	assert(value == 3, "Wrongly formed test command");

	cl.undo();
	assert(value == 1);
	cl.undo();
	assert(value == 0);

	cl.redo();
	assert(value == 1);
	cl.redo();
	assert(value == 3);

	assert(cl.canRedo() == false);
}

/// Test adding command removes redoable commands
unittest
{
	int value;
	CommandLog cl = new CommandLog();

	auto incrementOne = new TestCommand(() { value++; }, () { value--; });
	auto incrementTwo = new TestCommand(() { value += 2; }, () { value -= 2; });
	auto incrementBig = new TestCommand(() { value += 50; }, () { value -= 50; });

	incrementOne.run();
	cl.add(incrementOne);
	assert(value == 1);

	incrementTwo.run();
	cl.add(incrementTwo);
	assert(value == 3);

	cl.undo();
	assert(value == 1);
	// incrementTwo is now future undoable command

	incrementBig.run();
	cl.add(incrementBig);
	assert(value == 51);

	cl.undo();
	assert(value == 1);

	cl.undo();
	assert(value == 0);

	//log should now be empty
	assert(cl.canUndo() == false);
}
