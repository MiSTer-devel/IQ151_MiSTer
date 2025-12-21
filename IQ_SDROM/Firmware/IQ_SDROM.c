//#include "stdarg.h"


#include "Common_Firmware/uart.h"
#include "Common_Firmware/spi.h"
#include "Common_Firmware/minfat.h"
//#include "fat.h"
//#include "small_printf.h"


#define SIGNAL_LED_BASE 0xFFFFFFA0
#define DATA_INOUT_BASE 0xFFFFFFC0
#define STATUS_OUT_BASE 0xFFFFFFC4 // write STB; read IBF
#define STATUS_IN_BASE  0xFFFFFFC8 // write ACK; read OBF

                      
#define HW_SIGNAL_LED *(volatile unsigned int *)(SIGNAL_LED_BASE)
#define HW_DATA_INOUT *(volatile unsigned int *)(DATA_INOUT_BASE)
#define HW_STATUS_OUT *(volatile unsigned int *)(STATUS_OUT_BASE)
#define HW_STATUS_IN *(volatile unsigned int *)(STATUS_IN_BASE)

#define FAT_MAX_PATH 128
  
static unsigned char buf[512];
static unsigned char param[FAT_MAX_PATH];
static unsigned long size; 
DIRENTRY *dirEntry;
static char led;
static char bit2status;
static char bit5status;
static char currentDirLevel; // 0 = /IQ151/

int fileSearchMatch(const char *fn)
{	
	return 1;
}

void TunOnLed()
{
	led = 1;
	HW_SIGNAL_LED = led;
}

void TunOffLed()
{
	led = 0;
	HW_SIGNAL_LED = led;	
}

void BlinkLed()
{
	led = ~led;
	HW_SIGNAL_LED = led;
}


void Wait(unsigned long ms)	
{
	unsigned long endTime = getmsCounter() + ms;	
	while(1)
	{
		if (getmsCounter() > endTime)
			return;		
	}
}

// char ToLower(char ch)
// {
	// if (ch >= 65 && ch <= 90)
		// return ch + 32;
	// return ch;
// }

char ToUpper(char ch)
{
	if (ch >= 97 && ch <= 61)
		return ch - 32;
	return ch;
}

char GetSlashIndexes(char path[], char slashIndexes[])
{
	char dirUp[] = "../";
	char d = 0;
	char j = 0;
	char totalSlashes = 0;
	char currentSlash = 0;
	while (path[j] != '\0')
	{
		if (path[j] == dirUp[d])
			d++;
		else
			d = 0;
		if (path[j++] == '/')
		{
			if (d == 3) // .. dir = ignore this and previous
			{
				if (currentSlash > 0)
					currentSlash -= 1;// remove .. and previous dir from array slashIndexes
			}
			else
				slashIndexes[currentSlash++] = totalSlashes;
			totalSlashes++;
			d = 0;
		}
		else
		if (path[j] == '\0')
			slashIndexes[currentSlash++] = totalSlashes;
	}

	return currentSlash - 1;
}


// char GetNumberOfSlashes(char path[])
// {
	// char dirUp[] = "../";
	// char d = 0;
	// char j = 0;
	// char totalSlashes = 0;
	// char currentSlash = 0;
	// while (path[j] != '\0')
	// {
		// if (path[j] == dirUp[d])
			// d++;
		// else
			// d = 0;
		// if (path[j++] == '/')
			// totalSlashes++;
	// }
	// puts("d=");
	// puts(d);
	// puts("=d");
	// if (d == 3)
	// {
		// puts("odebiram 2 \xD\xA");
		// totalSlashes = totalSlashes - 3; // remove / + .. + / previous dir
	// }
	// return totalSlashes;
// }
 
char GetSubPathById(char path[], char SubPathId, char* result, char *isFile, char *isBasFile)
{
	char bas[] = ".bas";
	char currentSlash = 0;
	char src = 0;
	char dst = 0;
	char b = 0;		// index for .bas 
	char up = 0;	// index for ..
	while (1)
	{
		if (path[src] == '\0')
			break;
		if (path[src] == '/')
		{
			if (currentSlash == SubPathId)
				break;
			else
				currentSlash++;
			up = 0;
		}
		else
		{
			if (SubPathId == currentSlash)
				result[dst++] = path[src];
			if (ToLower(path[src]) == bas[b])
				b++;
			else
				b = 0;
			if ((path[src] == '.') && (up < 2))
				up++;
			else
				up = 99;
		}
		src++;
	}
	result[dst] = '\0';
	if (up == 1)
		result[0] = '\0';
	*isFile = ((path[src] == '\0') && (up != 1)) ? 1 : 0;
	*isBasFile = ((*isFile) & (b == 4)) ? 1 : 0;
	puts("(b=");
	putchar(b);
	puts(")");
	if (*isBasFile)
		puts("\xD\xAJe to bas ... ");
	if (*isFile)
		puts("Je to FILE ... ");
	if (b == 4)
		puts("b == 4 \xD\xA");

	
	
	return (currentSlash == SubPathId) ? 1 : 0;
}

void ChangeToIQRootDirectory()
{
	puts("Changing dir to /IQ151/ ");
	ChangeDirectory(0);	
	ChangeDirectoryByName("IQ151      ");
	currentDirLevel = 0;
}

char GetByte()
{		
	// custom bit-bang protocol!!
	HW_STATUS_IN = bit2status;   // flip bit 2 (PC[2])... I'm ready to read a byte
	bit2status = (~bit2status) & 0x01;
	while (HW_STATUS_IN == bit5status) // checking bit 5 (PC[5]) ... flip = byte is available
		;     // wait until IQ151 write byte for me
    char ch = (char)HW_DATA_INOUT;
	bit5status = (~bit5status) & 0x01;
	BlinkLed();
	putchar(ch);
    return ch;
}

void SendByte(const char ch)
{		
// nemám tady zkontrolovat IBF = 0 ???
	while (HW_STATUS_OUT & 0x01 == 1) // while input buffer full (IBF)
		; //Wait(1);     // wait until IQ151 read given byte
	HW_DATA_INOUT = ch; // send data to 8255 PA port
	HW_STATUS_OUT = 0;  // strobe (STB)
	while (HW_STATUS_OUT & 0x01 == 0) // wait till IBF get 0? .....1
		;//Wait(1);     
	HW_STATUS_OUT = 1;  // no strobe
	while (HW_STATUS_OUT & 0x01 == 1) // while input buffer full (IBF)
		;//Wait(1);     // wait until IQ151 read given byte
	BlinkLed();
	//putchar(ch);
}
	
void SendFile(const char *fileName, char isBasicFile)
{
	TunOnLed();
	fileTYPE ft;
	int i;
	if(FileOpen(&ft, fileName))				
	{
		size = ft.size; 	
		do
		{
			FileReadSector(&ft, buf); 			
			for (i = 0; i < 512; i++)
			{
				BlinkLed(); // blink LED each byte
				if (size == 0)
					break;							
				SendByte(buf[i]);
				size--;
			}			
			FileNextSector(&ft, 1);
		} while (size > 0);
	}
	else
		; //puts("Opening file error\n");
	if (isBasicFile)
		SendByte(27); // ESC
	TunOffLed();
	return;	
}	

void SendDir(const char* dirName)
{
	int i;	
	
	// find and send all subdirectories
	dirEntry = NextDirEntry(1, &fileSearchMatch);
	do
	{
		if (dirEntry->Attributes & ATTR_DIRECTORY)
		{	
			if (compare((const char*)dirEntry->Name, ".          ", 11) == 0)
				continue;

			// don't send ".." dir entry for IQ151 folder = don't allow to get upper
			if ((compare((const char*)dirEntry->Name, "..         ", 11) == 0) &&
				(currentDirLevel == 0))
				continue;
						
			SendByte('/'); // folder name starts with /
			if (longfilename[0] != '\0')
			{
				i=0;
				while (longfilename[i] != '\0')
					SendByte(longfilename[i++]);			
			}
			else				
				for (i=0; i<11; i++)
				{	
					if (dirEntry->Name[i] != ' ')
						SendByte(dirEntry->Name[i]);			
				}
			SendByte(0); // folder name ends with \0			
		}
	} while (dirEntry = NextDirEntry(0, &fileSearchMatch));
	
	// find and send all files
	dirEntry = NextDirEntry(1, &fileSearchMatch);
	do
	{
		if (!(dirEntry->Attributes & (ATTR_VOLUME | ATTR_DIRECTORY)))
		{			
			// if there is no longname, send "short name" variable content
			if (longfilename[0] != '\0')
			{
				i=0;
				while (longfilename[i] != '\0')
					SendByte(longfilename[i++]);			
			}
			else				
				for (i=0; i<11; i++)	
				{					
					if (dirEntry->Name[i] != ' ')
						SendByte(dirEntry->Name[i]);
					if (i == 7)
						SendByte('.'); 
				}
			SendByte(0); // file name ends with \0
		}						
	} while (dirEntry = NextDirEntry(0, &fileSearchMatch));
	SendByte(13); // directory list transfer to IQ  ends with \13
	SendByte(0); 
	TunOffLed();
}
		
int main(int argc, char **argv)
{	
	// Initializing SD card
	spi_init();
	// Hunting for partition
	FindDrive();	
	ChangeToIQRootDirectory();

    HW_STATUS_IN  = 0;   // ack_n = 0 ... I'm NOT ready to read a byte	
	HW_STATUS_OUT = 1;   // stb_n = 1 ... No new byte sent
	SendFile("__BLOADER.BAS", 0x01);    
	HW_STATUS_IN  = 1;   // ack_n = 1 ... I'm ready to read a byte	
	
	char len;
	char i;
	char slashes;
	char slash;
	char isFile;
	char isBasFile;
	char result[100];	
	char slashIndexes[25];
	
	while (1)
	{
		bit2status = 1; // custom bit-bang initialization
		bit5status = 0;
		char c = GetByte();
				
		switch (c)
		{			
			// Send SubDirs to IQ
			case 130:		
				len = GetByte();
				if (len > FAT_MAX_PATH)
					continue;
				for (i = 0; i < len; i++)
					param[i] = GetByte();
				puts("Changing to / \xD\xA");
				ChangeToIQRootDirectory();
				//slashes = GetNumberOfSlashes(param);
				
				
				slashes = GetSlashIndexes(param, slashIndexes);
				currentDirLevel = slashes; // ignoring 1st slash = 0
				
				//puts("Dir Leve = ");
				//puts(currentDirLevel);
				//puts("\xD\xA");
				for (slash = 1; slash <= slashes; slash++)
				{
					//GetSubPathById(param, slash, result, &isFile, &isBasFile);
					GetSubPathById(param, slashIndexes[slash], result, &isFile, &isBasFile);
					puts("Changing dir to ");
					puts(result);
					puts("\xD\xA");
					ChangeDirectoryByName(result);
				}
				SendDir(param);
				break;		
				
			// Send File to IQ
			case 131:				
				len = GetByte();
				if (len > FAT_MAX_PATH)
					continue;
				for (i = 0; i < len; i++)
					param[i] = GetByte();
				
				ChangeToIQRootDirectory();
				//slashes = GetNumberOfSlashes(param);
				
				
				slashes = GetSlashIndexes(param, slashIndexes);
				currentDirLevel = slashes - 2; // ignore 1st slash + last before filename
				
				for (slash = 1; slash <= slashes; slash++)
				{
					//GetSubPathById(param, slash, result, &isFile, &isBasFile);
					GetSubPathById(param, slashIndexes[slash], result, &isFile, &isBasFile);
					if (!isFile)
					{
						puts("Changing to ");
						puts(result);
						puts("**");
						ChangeDirectoryByName(result);
					}
					else
					{
						if (isBasFile)
							puts("Sending BAS file ->");
						else
							puts("Sending file ->");
						puts(result);
						puts("\xD\xA");
						SendFile(result, isBasFile);	
puts("Hotovo \xD\xA")					;	
//SendByte(27); // ESC
					}
				}
				break;
				
			default:
				// no action
				break;
		}
		
	}

	return(0);
}

