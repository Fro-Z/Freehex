module OffsetDisplay;
import gtk.DrawingArea;
import gtk.HBox;
import gtk.Style;
import gdk.RGBA;
import gtk.StyleContext;
import cairo.Context;
import cairo.FontFace;
import gtk.Widget;
import std.format;
import std.conv;
import TextStyle;

/**
*	OffsetDisplay is a widget that displays offset numbers in a specified format.
*/
class OffsetDisplay : DrawingArea
{
	/**
	* Create a new OffsetDisplay
	* @param spacing Spacing between individual offset labels
	*/
	this(GtkOrientation orientation, int spacing)
	{
		this.orientation = orientation;
		this.spacing = spacing;

		if (orientation == GtkOrientation.HORIZONTAL)
			setHexpand(true);
		else
			setVexpand(true);

		bgColor = new RGBA(233.0 / 255, 233.0 / 255, 233.0 / 255);
		addOnDraw(&drawCallback);

		textStyle.size = 11;
		textStyle.fontName = "monospace";
	}

	void setNumOfLabels(uint numOfLabels)
	{
		this.numOfLabels = numOfLabels;
		updateSizeRequest();
		queueDraw();
	}

	int cellWidth() const @property
	{
		return labelWidth;
	}

	int cellHeight() const @property
	{
		return labelHeight;
	}

	/**
	*	Set offset value to start at.
	*/
	void setStartOffset(ulong startOffset)
	{
		this.startOffset = startOffset;
		queueDraw();
	}

	/**
	* Set max offset and calculate space required for label
	*/
	void setMaxOffset(ulong maxOffset)
	{
		updateNumOfZeros(maxOffset);
		queueDraw();
	}

	/**
	* Set step between values in labels
	*/
	void setStep(int step)
	{
		this.step = step;
		queueDraw();
	}

	bool drawCallback(Scoped!Context c, Widget w)
	{
		//Background
		c.setSourceRgb(bgColor.red, bgColor.green, bgColor.blue);
		c.paint();

		textStyle.setupContext(c);
		updateCellSizes(c);

		int posX = 0;
		int posY = textStyle.size;
		foreach (uint i; 0 .. numOfLabels)
		{
			c.moveTo(posX, posY);

			string formatStr = "%0" ~ format("%d", numZeros) ~ "d";
			c.showText(format(formatStr, startOffset + i * step));

			if (orientation == GtkOrientation.HORIZONTAL)
				posX += spacing;
			else
				posY += spacing;
		}

		return true;
	}

private:
	void updateNumOfZeros(ulong maxNum)
	{
		int numberSize;
		while (maxNum > 0)
		{
			maxNum /= 10;
			numberSize++;
		}

		numZeros = numberSize;
		queueDraw();
	}

	void updateCellSizes(Context c)
	{
		char[] testText;
		foreach (i; 0 .. numZeros)
			testText ~= ['0'];

		cairo_text_extents_t ext;
		c.textExtents(testText.idup, &ext);
		labelWidth = to!int(ext.width);
		labelHeight = to!int(ext.height);

		updateSizeRequest();
	}

	void updateSizeRequest()
	{
		// Set minimum size to one cell
		// OffsetDisplay automatically expands in primary direction
		setSizeRequest(cellWidth, cellHeight);
	}

	ulong startOffset;
	uint step = 1;

	uint numOfLabels;
	int spacing;

	int numZeros = 2;

	int labelWidth;
	int labelHeight;

	GtkOrientation orientation;
	RGBA bgColor;
	TextStyle textStyle;

}
