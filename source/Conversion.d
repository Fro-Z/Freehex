module Conversion;
import std.format;
import std.exception;

/**
* Convert binary data to hexadecimal string
*/
string dataToString(const(ubyte)[] data)
{
	string str;
	foreach (const ubyte b; data)
		str ~= format("%02X", b);

	return str;
}

/**
* Convert hexadecimal string to binary data
*/
ubyte[] stringToData(string str)
{
	ubyte[] data = new ubyte[str.length / 2];
	for (size_t i = 0; i < (str.length / 2); i++)
	{
		string segment = str[i * 2 .. i * 2 + 2];
		enforce(segment.formattedRead!"%x"(data[i]) == 1,
				format("Error pasting data. Encountered %s", str));
	}
	return data;
}
