module DataDisplay;
import std.system;
import TranslatorPresenter;

interface IDataDisplay
{
	abstract void setData(const ubyte[], Endian);
	abstract void setPresenter(TranslatorPresenter);
}
