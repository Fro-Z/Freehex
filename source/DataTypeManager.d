module DataTypeManager;
import DataType;

/**
* Stores all known DataTypes
*/
class DataTypeManager
{
	this()
	{

	}

	void RegisterType(DataType type, bool isSigned)
	{
		if (isSigned)
			signedTypes ~= type;
		else
			unsignedTypes ~= type;
	}

	void RegisterBasicTypes()
	{
		RegisterType(new BasicDataType!byte(), true);
		RegisterType(new BasicDataType!ubyte(), false);

		RegisterType(new BasicDataType!short(), true);
		RegisterType(new BasicDataType!ushort(), false);

		RegisterType(new BasicDataType!int(), true);
		RegisterType(new BasicDataType!uint(), false);

		RegisterType(new BasicDataType!long(), true);
		RegisterType(new BasicDataType!ulong(), false);

		RegisterType(new BasicDataType!float(), true);
		RegisterType(new BasicDataType!double(), true);
	}

	const(DataType)[] getTypes() const
	{
		return signedTypes ~ unsignedTypes;
	}

	const(DataType)[] getSignedTypes() const
	{
		return signedTypes;
	}

	const(DataType)[] getUnsignedTypes() const
	{
		return unsignedTypes;
	}

private:
	DataType[] signedTypes;
	DataType[] unsignedTypes;
}
