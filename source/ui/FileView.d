module FileView;
import gtk.Grid;
import gtk.Label;
import HexPresenter;
import TextPresenter;
import DataViewport;
import gdk.Event;
import gtk.Widget;
import OffsetDisplay;
import gtk.Requisition;
import gtk.Scrollbar;
import gtk.Adjustment;
import gdk.Event;
import gtkc.gdktypes;
import gtk.Window;
import std.algorithm.comparison;
import gtk.Viewport;
import gtk.ScrolledWindow;
import gtk.HBox;
import gtk.Frame;
import Selection;
import gdk.RGBA;
import Interfaces;
import gdk.Keysyms;
import gtkc.gtktypes : ModifierType;

/**
Compound widget of HexViewport and TextViewport and offset marks. 
*/
class FileView : Grid
{
	this()
	{
		setColumnSpacing(SPACING);
		setRowSpacing(SPACING);

		createViewports();
		createOffsetDisplays();
		createScrollbar();

		addEvents(GdkEventMask.KEY_PRESS_MASK);
		addOnShow(&onShow);
		addOnKeyPress(&onKeyPress);

		selectionColor = new RGBA(163 / 255.0, 209 / 255.0, 1.0f);
	}

	void setWriter(ICursorWriter writer)
	{
		if (hexPresenter)
			hexPresenter.setWriter(writer);
		if (textPresenter)
			textPresenter.setWriter(writer);
	}

	/**
	* Set currently displayed data.
	*/
	void setViewportData(const ubyte[] data)
	{
		hexPresenter.setData(data);
		textPresenter.setData(data);
	}

	/**
	* Set size of a displayed file.
	*/
	void setFileSize(ulong fileSize)
	{
		this.maxAddress = fileSize > 0 ? fileSize - 1 : 0;
		offsetDispVertical.setMaxOffset(maxAddress);
		updateScrollbar();
	}

	/**
	* Move current address. Address will be adjusted to row start.
	*/
	void moveTo(ulong address)
	{
		ulong currentRow = clampRow(address / columns);
		currentAddress = currentRow * columns;
		updateScrollbar();
		offsetDispVertical.setStartOffset(currentAddress);

		if (onMove)
			onMove();
	}

	/// Set delegate to be called after current address is moved.
	void setOnMove(void delegate() onMoveDlg)
	{
		onMove = onMoveDlg;
	}

	ulong getCurrentAddress() const
	{
		return currentAddress;
	}

	uint bytesRequired() const
	{
		return columns * rows;
	}

	/// Get current selection
	Selection getSelection() const
	{
		return selection;
	}

	/// Set delegate to be called when selection changes
	void setOnSelectionUpdate(void delegate(Selection) del)
	{
		this.onSelectionUpdate = del;
	}

private:
	/*
	//////////////GDK Events//////////////
	*/

	void onShow(Widget w)
	{
		auto parentWin = cast(Window)getToplevel();
		if (parentWin)
			parentWin.addOnScroll(&onScroll);
		addEvents(GdkEventMask.SCROLL_MASK);
	}

	bool onScroll(Event e, Widget w)
	{
		GdkEventScroll* scrollEvent = e.scroll();

		if (scrollEvent && (scrollEvent.direction == GdkScrollDirection.UP
				|| scrollEvent.direction == GdkScrollDirection.DOWN))
			return scrollbar.onScrollEvent(scrollEvent);
		else
			return false;
	}

	bool onKeyPress(Event event, Widget w)
	{
		if (event.type == EventType.KEY_PRESS)
		{
			auto keyval = event.key.keyval;
			switch (keyval)
			{
			case GdkKeysyms.GDK_Left:
				moveSelectionBy(-1);
				return true;
			case GdkKeysyms.GDK_Right:
				moveSelectionBy(1);
				return true;
			case GdkKeysyms.GDK_Up:
				moveSelectionBy(-columns);
				return true;
			case GdkKeysyms.GDK_Down:
				moveSelectionBy(columns);
				return true;
			default:
				return false;
			}
		}

		return false;
	}

	/**
	* Calculates available column and row counts and update viewports.
	*/
	void onViewportSizeAllocate(Allocation a, Widget w)
	{
		immutable widthPerByte = hexViewport.cellWidth + textViewport.cellWidth;
		immutable horizontalFreeSpace = a.width - SPACING;
		immutable verticalFreeSpace = a.height;

		int newColumns = horizontalFreeSpace / widthPerByte;
		int newRows = verticalFreeSpace / hexViewport.cellHeight;

		//Always keep at least one column and row
		newColumns = max(newColumns, 1);
		newRows = max(newRows, 1);

		bool isResize = newColumns != columns || newRows != rows;
		columns = newColumns;
		rows = newRows;

		if (isResize)
		{
			updateViewportSizes();

			if (onMove)
				onMove();
		}
	}

	void onScrollbarValueChanged(Adjustment adj)
	{
		ulong newRow = cast(ulong)adj.getValue();

		auto newAddress = newRow * columns;
		if (newAddress != currentAddress)
		{
			moveTo(newAddress);
			updateViewportHighlights();
		}
	}

private:
	/*
	////////////// Selection //////////////
	*/
	void onCellSelect(int cellIdx, ModifierType state)
	{
		if (state & ModifierType.SHIFT_MASK)
		{
			//extend selection to here
			selectionInProgress = true;
			updateSelection(cellIdx);
		}
		else
			startSelection(cellIdx);
	}

	void onCellHover(int cellIdx)
	{
		if (selectionInProgress)
			updateSelection(cellIdx);
	}

	void onCellSelectEnd()
	{
		if (selectionInProgress)
			endSelection();
	}

	void startSelection(int cellIdx)
	{
		ulong filePos = cellIdx + currentAddress;

		if (filePos <= maxAddress)
		{
			selectionInProgress = true;
			selection.update(filePos, filePos);
			updateViewportHighlights();
		}
	}

	void updateSelection(int cellIdx)
	{
		ulong filePos = cellIdx + currentAddress;

		if (filePos <= maxAddress)
		{
			selection.secondAnchor = filePos;
			updateViewportHighlights();
		}
	}

	void endSelection()
	{
		selectionInProgress = false;
		if (onSelectionUpdate)
			onSelectionUpdate(selection);

		updateViewportHighlights();
	}

public:
	/// Advance selection start by one. 
	void advanceSelection()
	{
		ulong from = selection.lower + 1;
		ulong to = selection.upper;
		if (to < from)
			to++;

		if (to > maxAddress)
			return;

		selection.update(from, to);
		updateViewportHighlights();

		if (onSelectionUpdate)
			onSelectionUpdate(selection);
	}

	/// Move selection by offset (And reduce selection to cursor)
	void moveSelectionBy(long offset)
	{
		if (offset < 0 && -offset > selection.lower)
			return;

		ulong position = selection.lower + offset;
		if (position > maxAddress)
			return;

		selection.update(position, position);
		updateViewportHighlights();

		if (onSelectionUpdate)
			onSelectionUpdate(selection);
	}

	void resetSelection()
	{
		selection.update(0, 0);
		updateViewportHighlights();
	}

	void select(ulong from, ulong to)
	{
		from = min(from, maxAddress - 1);
		to = min(to, maxAddress - 1);

		selection.update(from, to);
		endSelection();
	}

private:
	/**
	* Update scrollbar so that the range properly repsenets rows in a file.
	*/
	void updateScrollbar()
	{
		ulong currentRow = clampRow(currentAddress / columns);
		ulong lastScrollableRow = clampRow(maxAddress / columns);
		scrollbarAdjustment.setUpper(cast(double)lastScrollableRow);
		scrollbarAdjustment.setValue(cast(double)currentRow);
	}

	/**
	* Clamp row number so that max value is the last scrollable row for the file.
	*/
	ulong clampRow(ulong originalRow)
	{
		ulong totalRows = (maxAddress + columns - 1) / columns; //count rows even when not fully occupied

		auto lastScrollableRow = totalRows;

		// Block scrolling after last row is already visible
		if (rows <= totalRows)
			lastScrollableRow -= rows - 3;
		else
			lastScrollableRow = 0; // prevent ulong underflow

		return min(originalRow, lastScrollableRow);
	}

	/**
	* Update column and row numbers of child widgets
	*/
	void updateViewportSizes()
	{
		textViewport.setSize(columns, rows);
		hexViewport.setSize(columns, rows);

		offsetDispHorizontal.setNumOfLabels(columns);

		offsetDispVertical.setNumOfLabels(rows);
		offsetDispVertical.setStep(columns);

		queueDraw();
	}

	void updateViewportHighlights()
	{
		ulong localStart = 0;
		if (selection.lower > currentAddress) //prevent overflows
			localStart = selection.lower - currentAddress;

		ulong localEnd = 0;
		if (selection.upper >= currentAddress)
		{
			localEnd = selection.upper - currentAddress;
			hexViewport.setHighlight(cast(int)localStart, cast(int)localEnd, selectionColor);
			textViewport.setHighlight(cast(int)localStart, cast(int)localEnd, selectionColor);
		}
		else
		{
			hexViewport.resetHighlight();
			textViewport.resetHighlight();
		}

	}

private:
	/*
	////////////// Construction //////////////
	*/
	void createScrollbar()
	{
		scrollbarAdjustment = new Adjustment(0, 0, 1, SCROLL_STEP_INCREMENT, 1, 1);
		scrollbarAdjustment.setStepIncrement(SCROLL_STEP_INCREMENT);
		scrollbarAdjustment.setPageSize(SCROLL_STEP_INCREMENT);
		scrollbarAdjustment.addOnValueChanged(&onScrollbarValueChanged);

		scrollbar = new Scrollbar(GtkOrientation.VERTICAL, scrollbarAdjustment);
		attach(scrollbar, 3, 1, 1, 1);
	}

	void createOffsetDisplays()
	{
		auto lblOffset = new Label("Offset");
		attach(lblOffset, 0, 0, 1, 1);

		offsetDispHorizontal = new OffsetDisplay(GtkOrientation.HORIZONTAL, hexViewport.cellWidth);
		attach(offsetDispHorizontal, 1, 0, 1, 1);
		offsetDispHorizontal.show();

		offsetDispVertical = new OffsetDisplay(GtkOrientation.VERTICAL, hexViewport.cellHeight);
		attach(offsetDispVertical, 0, 1, 1, 1);
		offsetDispVertical.show();
	}

	void createViewports()
	{
		hexViewport = new DataViewport();
		hexViewport.setOnCellSelect(&onCellSelect);
		hexViewport.setOnCellHover(&onCellHover);
		hexViewport.setOnCellSelectEnd(&onCellSelectEnd);
		hexPresenter = new HexPresenter(hexViewport);

		textViewport = new DataViewport();
		textViewport.setOnCellSelect(&onCellSelect);
		textViewport.setOnCellHover(&onCellHover);
		textViewport.setOnCellSelectEnd(&onCellSelectEnd);
		textPresenter = new TextPresenter(textViewport);

		auto viewportBox = new HBox(false, SPACING);
		viewportBox.setHexpand(true);
		viewportBox.packStart(hexViewport, false, false, 0);
		viewportBox.packStart(textViewport, false, false, 0);

		// Keep viewports in a ScrolledWindow so that their size can be shrunk
		auto resizableWin = new ScrolledWindow();
		resizableWin.addOnSizeAllocate(&onViewportSizeAllocate);
		resizableWin.addWithViewport(viewportBox);

		// Add encoding chooser to main window
		auto encodingChooser = textPresenter.createEncodingChooser();
		import HexEditor;

		HexEditor.editor.addToolbarWidget(encodingChooser);
		encodingChooser.show();

		attach(resizableWin, 1, 1, 2, 1);
		hexViewport.show();
		textViewport.show();
	}

private:
	enum SPACING = 5;
	enum SCROLL_STEP_INCREMENT = 3;
	enum LEFT_MOUSE_BUTTON = 1;

	ulong maxAddress;
	ulong currentAddress;

	int columns = 1;
	int rows = 1;

	bool selectionInProgress;
	Selection selection;

	DataViewport hexViewport;
	HexPresenter hexPresenter;

	DataViewport textViewport;
	TextPresenter textPresenter;

	OffsetDisplay offsetDispHorizontal;
	OffsetDisplay offsetDispVertical;

	Adjustment scrollbarAdjustment;
	Scrollbar scrollbar;

	RGBA selectionColor;
	void delegate() onMove;
	void delegate(Selection) onSelectionUpdate;

	invariant()
	{
		assert(columns > 0);
		assert(rows > 0);
	}
}
