module DataViewport;
import TextStyle;
import gtk.DrawingArea;
import cairo.Context;
import gtk.Widget;
import gdk.Event;
import gdk.RGBA;
import std.datetime;
import pango.PgCairo;
import pango.PgLayout;
import pango.PgFontDescription;
import std.conv;
import std.algorithm.comparison : min;
import gtkc.gtktypes : ModifierType;

/**
Base class for widgets that displays data in a fixed size grid.
Widgets that implement DataViewport should override getCellText()
*/
class DataViewport : DrawingArea, IDataViewport
{
	this()
	{
		addOnDraw(&drawCallback);
		style.fontName = "monospace";
		style.size = 11;
		setSize(1, 1);
		addEvents(GdkEventMask.KEY_PRESS_MASK);
		addEvents(GdkEventMask.BUTTON_PRESS_MASK);
		addOnButtonPress(&onButtonPress);
		addOnMotionNotify(&onMotionNotify);
		addOnButtonRelease(&onButtonRelease);

		setCanFocus(true);
		addOnFocusOut(&onFocusOut);
		addOnFocusIn(&onFocusIn);
	}

	/**
	* Proxy function for Widget.addOnKeyPress. Makes the function callable from IDataViewport interface.
	*/
	void addOnKeyPressProxy(bool delegate(Event, Widget) del)
	{
		addOnKeyPress(del);
	}

	/**
	* Set size of the viewport in cells
	*/
	void setSize(int newColumns, int newRows)
	{
		if (newColumns != columns || newRows != rows)
		{
			setSizeRequest(newColumns * cellWidth, newRows * cellHeight);
			forceQueueResize(); //Note: QueueResize does not work when called during gtk size allocation phase. Issue #3
		}

		columnCount = newColumns;
		rowCount = newRows;
		queueDraw();
	}

	int columns() const
	{
		return columnCount;
	}

	int rows() const
	{
		return rowCount;
	}

	/// Horizontal space required for a single byte-cell
	@property int cellWidth() const
	{
		return cast(int)(style.size * 2 * cellWidthScale);
	}

	/// Vertical space required for a single cell
	@property int cellHeight() const
	{
		return (style.size + 7);
	}

	/// TextStyle used for drawing
	ref const(TextStyle) textStyle() const
	{
		return style;
	}

	override void setPresenter(IDataPresenter presenter)
	{
		this.presenter = presenter;
	}

	override void redraw()
	{
		queueDraw();
	}

	/// Set multiplier to default cellWidth
	override void setCellWidthScale(float scale)
	{
		cellWidthScale = scale;
		queueResize();
		queueDraw();
	}

	/**
	* Register delegate to be called when cell is selected.
	* The delagate has signature of void func(int cellIdx)
	* where cellIdx is the index of the cell in the DataViewport.
	*/
	void setOnCellSelect(void delegate(int cellIdx, ModifierType mod) del)
	{
		this.onCellSelectCallback = del;
	}

	/**
	* Register delegate to be called when pointer is hovering above a cell.
	* The delagate has signature of void func(int cellIdx)
	* where cellIdx is the index of the cell in the DataViewport.
	*/
	void setOnCellHover(void delegate(int cellIdx) del)
	{
		this.onCellHoverCallback = del;
	}

	/**
	* Register delegate to be called when selection is interrupted
	* by either mouse release or losing focus.
	*/
	void setOnCellSelectEnd(void delegate() del)
	{
		this.onCellSelectEndCallback = del;
	}

	/// Hide current highlight
	void resetHighlight()
	{
		highlight.isVisible = false;
	}

	/**
	* Set start and end point for highlight. Highlight is used to mark selection by FileView.
	*/
	void setHighlight(int start, int end, RGBA color)
	{
		highlight.start = start;
		highlight.end = end;
		highlight.isVisible = true;
		highlight.color = color;
		queueDraw();
	}

private:

	bool onButtonPress(Event event, Widget widget)
	{
		if (event.type == EventType.BUTTON_PRESS)
		{
			if (event.button.button == LEFT_MOUSE_BUTTON)
				createCellClickEvent(event.button.x, event.button.y, event.button.state);
		}

		return false;
	}

	bool onMotionNotify(Event event, Widget widget)
	{
		createCellHoverEvent(event.button.x, event.button.y);

		return false;
	}

	bool onFocusOut(Event e, Widget w)
	{
		if (onCellSelectEndCallback)
		{
			onCellSelectEndCallback();
		}

		return false;
	}

	bool onFocusIn(Event e, Widget w)
	{

		return false;
	}

	bool onButtonRelease(Event event, Widget widget)
	{
		if (event.button.button == LEFT_MOUSE_BUTTON)
			if (onCellSelectEndCallback)
			{
				onCellSelectEndCallback();
				grabFocus();
			}

		return false;
	}

	/// Create cell click event from local coordinates
	void createCellClickEvent(double x, double y, ModifierType state)
	{
		int cellX = cast(int)(x / cellWidth);
		int cellY = cast(int)(y / cellHeight);

		int cellPos = cellX + cellY * columns;
		if (onCellSelectCallback)
			onCellSelectCallback(cellPos, state);
	}

	/// Create cell hover event from local coordinates
	void createCellHoverEvent(double x, double y)
	{
		int cellX = cast(int)(x / cellWidth);
		int cellY = cast(int)(y / cellHeight);

		int cellPos = cellX + cellY * columns;
		if (onCellHoverCallback)
			onCellHoverCallback(cellPos);
	}

	void drawTextAtPos(Context c, int posX, int posY, string text)
	{
		c.moveTo(posX, posY);
		c.showText(text);
	}

	void drawBackground(Context c)
	{
		c.setSourceRgba(1.0, 1.0, 1.0, 1.0);
		c.rectangle(0, 0, cellWidth * columns, cellHeight * rows);
		c.fill();

		//draw highlight backgrounds
		if (highlight.isVisible)
			drawHighlightBackground(c);
	}

	void highlightFirstRow(Context c)
	{
		int posX = highlight.start % columns;
		int posY = highlight.start / columns;
		int firstRowLength = min(columns - posX, highlight.length) + 1;
		c.rectangle(posX * cellWidth, posY * cellHeight, cellWidth * firstRowLength, cellHeight);
		c.fill();
	}

	void highlightLastRow(Context c)
	{
		if (highlight.start / columns == highlight.end / columns)
			return; //highlight does did not cross the line

		int posX = highlight.end % columns;
		int posY = highlight.end / columns;

		c.rectangle(0, posY * cellHeight, cellWidth * (posX + 1), cellHeight);
		c.fill();
	}

	void highlightMiddle(Context c)
	{
		int height = highlight.end / columns - highlight.start / columns - 1; //subtracting for first and last row
		if (height <= 0)
			return;

		int posY = highlight.start / columns + 1;

		c.rectangle(0, posY * cellHeight, cellWidth * (columns), cellHeight * height);
		c.fill();
	}

	void drawHighlightBackground(Context c)
	{
		c.save();
		c.setSourceRgb(highlight.color.red, highlight.color.green, highlight.color.blue);

		highlightFirstRow(c);
		highlightLastRow(c);
		highlightMiddle(c);

		c.restore();
	}

	bool drawCallback(Scoped!Context c, Widget widget)
	{
		queueResizeIfForced();
		drawBackground(c);
		textStyle.setupContext(c);

		foreach (int i; 0 .. columns * rows)
		{
			int posX = (i % columns) * cellWidth;
			int posY = (i / columns) * cellHeight + textStyle.size;

			if (presenter)
				drawTextAtPos(c, posX, posY, presenter.getCellText(i));
		}
		return true;
	}

	// Workaround for Issue #3
	void forceQueueResize()
	{
		forceResize = true;
	}

	//Workaround for Issue #3
	void queueResizeIfForced()
	{
		if (forceResize)
			queueResize();
		forceResize = false;
	}

private:
	bool forceResize;

	int columnCount;
	int rowCount;

	float cellWidthScale = 1;

	TextStyle style;
	IDataPresenter presenter;

	Highlight highlight;
	void delegate(int, ModifierType) onCellSelectCallback;
	void delegate(int) onCellHoverCallback;
	void delegate() onCellSelectEndCallback;

	enum LEFT_MOUSE_BUTTON = 1;
}

/**
* Common interface for presenter classes used with DataViewport
*/
interface IDataPresenter
{
	/// Get text to display at cell position
	abstract string getCellText(int cellIdx) const;
}

interface IDataViewport
{
	abstract void setCellWidthScale(float scale);
	abstract void setPresenter(IDataPresenter presenter);
	abstract void redraw();
	abstract void addOnKeyPressProxy(bool delegate(Event, Widget));
}

struct Highlight
{
	int start;
	int end;

	@property length() const
	{
		return end - start;
	}

	bool isVisible;
	RGBA color;
}
