module DataType;
import std.conv;
import BasicTypeBox;
import gtk.Widget;
import DataDisplay;
import std.system;
import std.algorithm.mutation;
import std.exception;
import std.format;
import std.array;

class InvalidStringException : Exception
{
	this(string msg)
	{
		super(msg);
	}
}

/**
* Data type for purposes of DataTranslator and StructViewer
*/
abstract class DataType
{
	this(string name, uint size)
	{
		this.typeName = name;
		this.sizeInBytes = size;
	}

	/// Size of type in bytes
	uint size() const
	{
		return sizeInBytes;
	}

	string name() const
	{
		return typeName;
	}

	bool isSigned() const
	{
		return false;
	}

	/// Get string representation of bytes as this data type
	abstract string fromData(in ubyte[] data, Endian endian) const;

	/**
	* Get byte representation of a string.  Throws InvalidStringException if string is not a valid type representation.
	*/
	abstract ubyte[] fromString(in string str, Endian endian) const;

	/**
	* Create a widget best suitable to represent this data type in Translator.
	* The widget must implement IDataDisplay interface
	*/
	abstract Widget createDisplayWidget() const
	out (result)
	{
		assert(cast(IDataDisplay)result, "Widget must implement IDataDisplay interface");
	}
	body
	{
		//	As of DMD version 2.073 in and out contracts on require function body.
		assert(false,
				"createDisplayWidget dummy implementation. Implement yourself in a derived type.");
	}

protected:
	enum INVALID_SIZE_STRING = "Invalid size";

private:
	uint sizeInBytes;
	string typeName;
}

/**
Template for basic types known at compile time
*/
class BasicDataType(T) : DataType
{
	this()
	{
		super(T.stringof, T.sizeof);
	}

	override string fromData(in ubyte[] data, Endian endian) const
	{
		if (data.length < size)
			return INVALID_SIZE_STRING;

		// Reverse byte order if endianness doesn't match
		if (endian == std.system.endian)
		{
			T* tmp = cast(T*)data.ptr;
			return to!string(*tmp);
		}
		else
		{
			ubyte[] slice = data[0 .. size].dup;
			reverse(slice);
			T* tmp = cast(T*)slice.ptr;
			return to!string(*tmp);
		}
	}

	override ubyte[] fromString(in string str, Endian endian) const
	{
		import std.conv : parse;

		T value;

		import std.array : replace;

		string strDup = str.dup.replace(",", "."); //Replace locale defined "," back into "." (Parse does not respect locale)
		try
		{
			value = parse!T(strDup);
		}
		catch (Exception e)
		{
			throw new InvalidStringException(format("Invalid string for a type %s", T.stringof));
		}

		if (strDup.length > 0)
			throw new InvalidStringException("Could not convert whole string");

		ubyte* valuePtr = cast(ubyte*)&value;
		ubyte[] valueSlice = valuePtr[0 .. T.sizeof];

		if (endian == std.system.endian)
			return valueSlice.dup;
		else
		{
			ubyte[] reversed = valueSlice.dup;
			reverse(reversed);
			return reversed;
		}
	}

	override bool isSigned() const
	{
		import std.traits : isSigned;

		static if (isSigned!T)
			return true;
		else
			return false;
	}

	override Widget createDisplayWidget() const
	{
		return new BasicTypeBox(this);
	}

}

unittest  // Test returns invalid size
{
	auto uintType = new BasicDataType!uint();
	ubyte[] data = [0xFF];
	assert(uintType.fromData(data, Endian.littleEndian) == DataType.INVALID_SIZE_STRING);
}

unittest  // Test littleEndian
{
	auto uintType = new BasicDataType!uint();
	ubyte[] data = [0xFC, 0xDD, 0x10, 0x05];
	string resultStr = uintType.fromData(data, Endian.littleEndian);
	assert(resultStr == "84991484");

	ubyte[] convBack = uintType.fromString(resultStr, Endian.littleEndian);
	assert(convBack == data);
}

unittest  // Test bigEndian
{
	auto uintType = new BasicDataType!uint();
	ubyte[] data = [0xFC, 0xDD, 0x10, 0x05];
	string resultStr = uintType.fromData(data, Endian.bigEndian);
	assert(resultStr == "4242345989");

	ubyte[] convBack = uintType.fromString(resultStr, Endian.bigEndian);
	assert(convBack == data);
}
