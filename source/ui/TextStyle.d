module TextStyle;
import cairo.Context;

/**
Text Style structure used for grouping Cairo font style settings.
*/
struct TextStyle
{
	int size;
	string fontName;

	void setupContext(scope Context c) const
	{
		c.selectFontFace(fontName, cairo_font_slant_t.NORMAL, cairo_font_weight_t.NORMAL);
		c.setSourceRgb(0.0, 0.0, 0.0);
		c.setFontSize(size);
	}
}
