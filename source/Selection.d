module Selection;

/**
* Struct that represents inclusive selection between two points in a file (anchors).
* There are no requirements for order of anchors. If you require orde
*/
struct Selection
{
	ulong firstAnchor;
	ulong secondAnchor;

	/// Update selection to new bounds
	void update(ulong from, ulong to)
	{
		firstAnchor = from;
		secondAnchor = to;
	}

	/// Lower bound of the selection
	@property ulong lower() const
	{
		return firstAnchor < secondAnchor ? firstAnchor : secondAnchor;
	}

	/// Upper bound of the selection
	@property ulong upper() const
	{
		return firstAnchor > secondAnchor ? firstAnchor : secondAnchor;
	}

	/// Number of bytes selected, including the upper bound
	@property ulong length() const
	{
		return upper - lower + 1;
	}
}
