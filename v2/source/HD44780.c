/*
 * This file is part of the Bus Pirate project (buspirate.com).
 *
 * Originally written by hackaday.com <legal@hackaday.com>
 *
 * To the extent possible under law, hackaday.com <legal@hackaday.com> has
 * waived all copyright and related or neighboring rights to Bus Pirate. This
 * work is published from United States.
 *
 * For details see: http://creativecommons.org/publicdomain/zero/1.0/.
 *
 *    This program is distributed in the hope that it will be useful,
 *    but WITHOUT ANY WARRANTY; without even the implied warranty of
 *    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 *
 */

#include "m_i2c_1.h"
#include "base.h"

//PCF8574 I2C write address (0x40 with all ADDR pins to ground)
#define PCF8574_ADDRESS_WRITE 0x40

//Define how the PCF8574 pins connect to the LCD
#define PCF8574_LCD_RS 0b10000000
#define PCF8574_LCD_RW 0b01000000
#define PCF8574_LCD_EN 0b00100000
#define PCF8574_LCD_D4 0b00000001
#define PCF8574_LCD_D5 0b00000010
#define PCF8574_LCD_D6 0b00000100
#define PCF8574_LCD_D7 0b00001000
#define PCF8574_LCD_LED 0b00010000

//RS (register select) pin states
#define HD44780_COMMAND 0 
#define HD44780_DATA 1 

//
//HD44780 commands and related options
//
#define CMD_CLEARDISPLAY 	0b00000001 //82us-1.64ms

#define CMD_RETURNHOME 		0b00000010 //40us-1.64ms

#define CMD_ENTRYMODESET 	0b00000100 //40us
#define INCREMENT 0b10
#define DECREMENT 0b00
#define DISPLAYSHIFTON 0b1
#define DISPLAYSHIFTOFF 0

#define CMD_DISPLAYCONTROL 	0b00001000 //40us
#define DISPLAYON 0b100
#define DISPLAYOFF 0
#define CURSERON 0b10
#define CURSEROFF 0
#define BLINKON 0b1
#define BLINKOFF 0

#define CMD_CURSERDISPLAYSHIFT 0b00010000 //40us
#define DISPLAYSHIFT 0b1000
#define CURSERMOVE 0
#define SHIFTRIGHT 0b100
#define SHIFTLEFT 0

#define CMD_FUNCTIONSET 	0b00100000 //40us
#define DATAWIDTH8 0b10000
#define DATAWIDTH4 0
#define DISPLAYLINES2 0b1000
#define DISPLAYLINES1 0
#define FONT5X10 0b100
#define FONT5X7 0
#define MODULE24X4 0b1

#define CMD_SETCGRAMADDR 	0b01000000 //40us
//6bit character generator RAM address

#define CMD_SETDDRAMADDR 	0b10000000 //40us
//7bit display data RAM address

//configuration structure
extern struct _modeConfig modeConfig;

/*
struct _HD44780_4bit_interface {
	unsigned char EN:1; //clock, active high
	unsigned char RS:1; //register select, 0=command, 1=text
	unsigned char RW:1; //read write, 0=, 1=
	unsigned char D4:1;
	unsigned char D5:1;
	unsigned char D6:1;
	unsigned char D7:1;
}
*/
struct _HD44780_interface {
	unsigned char EN:1; //clock, active high
	unsigned char RS:1; //register select, 0=command, 1=text
	unsigned char RW:1; //read write, 0=write, 1=read
	unsigned char LED:1; //LED on IO board, 0=on, 1=off
	//unsigned char dat; //8 data bits
} HD44780;

void HD44780_Term(void); //outputs typed text to the LCD
void HD44780_Reset(void); //reset the LCD to 4 bit mode
void HD44780_Init(unsigned char displaylines); //initialize LCD to 4bit mode with typical settings and X displaylines
void HD44780_WriteString(char *s); //write a string to the LCD
void HD44780_WriteByte(unsigned char reg, unsigned char dat); //write a byte to LCD to register REG
void HD44780_WriteNibble(unsigned char reg, unsigned char dat);//write 4 bits to LCD to register REG
void HD44780_I2Cwrite(unsigned char datout); //abstracts data output to PCF8574 IO expander over I2C bus
unsigned char HD44780_I2Cread(void);
unsigned char HD44780_ReadNibble(unsigned char reg);
unsigned char HD44780_ReadByte(unsigned char reg);

//this function links the underlying LCD functions to generic commands that the bus pirate issues
//put most used functions first for best performance
void HD44780Process(unsigned char cmd, unsigned int numVal, unsigned int repeatVal){
	static unsigned char c;
	static unsigned int i;
	switch(cmd){
		case CMD_READ:
			bpWmessage(MSG_READ);
			c=HD44780_ReadByte(HD44780.RS);
			bpWbyte(c);
			bpWBR;
			break;
		case CMD_WRITE:
			if(repeatVal==1){
				if(HD44780.RS == HD44780_COMMAND){
					bpWstring("CMD ");	
				}else{
					bpWstring("DAT ");
				}
				bpWmessage(MSG_WRITE);
				bpWbyte(numVal);
				HD44780_WriteByte(HD44780.RS, numVal);
			}else{
				bpWmessage(MSG_WRITEBULK);
				bpWbyte(numVal);
				bpWstring(" , ");
				bpWbyte(repeatVal);
				bpWstring(" TIMES");
				for(i=0;i<repeatVal;i++)HD44780_WriteByte(HD44780.RS, numVal);
			}
			bpWBR;
			break;
		case CMD_STARTR:
		case CMD_START:
			//next byte is command
			HD44780.RS=HD44780_COMMAND;
			bpWline("HD44780 RS LOW, COMMAND MODE");
			break;
		case CMD_STOP:
			//next byte is data
			HD44780.RS=HD44780_DATA;
			bpWline("HD44780 RS HIGH, DATA MODE");
			break;
		case CMD_PRESETUP:
			//set the options avaiable here....
			modeConfig.allowlsb=0;
			modeConfig.allowpullup=1; 
			modeConfig.HiZ=1;//yes, always HiZ

			HD44780.RS=HD44780_DATA;
			break;
		case CMD_SETUP:
			//-- Ensure pins are in high impedance mode --
			SDA_TRIS=1;
			SCL_TRIS=1;
			//writes to the PORTs write to the LATCH
			SCL=0;			//B8 scl 
			SDA=0;			//B9 sda
			bpWline("LCD type:\x0D\x0A 1. HD44780 (using PCF8574 IO expander)");
			c=bpUserNumberPrompt(1, 1, 1);
			bpWline("HD44780 LCD TESTER");
			bpWline("REQUIRES PCF8574 I2C IO EXPANDER");
			break;
		case CMD_CLEANUP: //no cleanup needed...
			break;
		case CMD_MACRO:
			switch(numVal){
				case 0://menu
					bpWline(" 0.Macro menu\x0D\x0A 1.LCD Reset\x0D\x0A 2.Init LCD\x0D\x0A 3.Clear LCD\x0D\x0A 4.Cursor position ex:(4:0)\x0D\x0A 5.Write test text\x0D\x0A 6.Write :number test numbers ex:(6:80)\x0D\x0A 7.Write :number test characters ex:(7:80)\x0D\x0A 8.Insert text at cursor");
					break;
				case 1:
					bpWline("RESET");
					HD44780_Reset();
					break;
				case 2:
					bpWline("Display lines:\x0D\x0A 1. 1 \x0D\x0A 2. Multiple");
					c=bpUserNumberPrompt(1, 2, 2);

					HD44780_Reset();
					bpWline("RESET");
					if(c==1) HD44780_Init(DISPLAYLINES1); else HD44780_Init(DISPLAYLINES2);
					bpWline("INIT");
					break;		
				case 3: //Clear LCD and return home
					HD44780_WriteByte(HD44780_COMMAND, CMD_CLEARDISPLAY);
					bpDelayMS(15);//delay 15ms
					bpWline("CLEARED");
					break;	
				case 4: //set cursor position to repeatVal
					HD44780_WriteByte(HD44780_COMMAND, CMD_SETDDRAMADDR | (unsigned char)repeatVal);
					break;
				case 5: //write test text
					HD44780_WriteByte(HD44780_COMMAND, CMD_CLEARDISPLAY);//Clear LCD and return home
					bpDelayMS(15);//delay 15ms
					HD44780_WriteByte(HD44780_COMMAND, CMD_SETDDRAMADDR | 0);//position at beginning
					HD44780_WriteString("-=*=- LCD test. Bus Pirate. www.buspirate.com Hack a Day. www.hackaday.com -=*=-");
					break;
				case 6: //write numbers	
					HD44780_WriteByte(HD44780_COMMAND, CMD_CLEARDISPLAY);//Clear LCD and return home
					bpDelayMS(15);//delay 15ms
					c=0x30;
					for(i=0; i<repeatVal; i++){
						if(c>0x39) c=0x30;
						HD44780_WriteByte(HD44780_DATA, c);
						c++;
					}
					break;	
				case 7://write characters				
					HD44780_WriteByte(HD44780_COMMAND, CMD_CLEARDISPLAY); //Clear LCD and return home
					bpDelayMS(15);//delay 15ms
					c=0x21; //start character (!)
					if(repeatVal==0) repeatVal=80;
					for(i=0; i<repeatVal; i++){
						if(c>127)c=0x21;
						HD44780_WriteByte(HD44780_DATA, c);
						c++;
					}
					break;
				case 8://terminal mode/pass through
						bpWline("Enter text to insert at the curser position.");
						HD44780_Term();
					break;
				default:
					bpWmessage(MSG_ERROR_MACRO);
			}
			break;
		default:
			bpWmessage(MSG_ERROR_MODE);
	}

}

//outputs typed text to the LCD
void HD44780_Term(void){
	#define HD44780_TERM_SIZE 24
	unsigned int currentByte=0, i;
	unsigned char tinput[HD44780_TERM_SIZE];

	while(bpGetUserInput(&currentByte, HD44780_TERM_SIZE, tinput)==0);

	for(i=0;i<currentByte; i++) HD44780_WriteByte(HD44780_DATA, tinput[i]);

}

//initialize LCD to 4bits with standard features
//displaylines=0 for single line displays, displaylines=1 for multiline displays
void HD44780_Init(unsigned char displaylines){
	//Function set
	HD44780_WriteByte(HD44780_COMMAND, (CMD_FUNCTIONSET + DATAWIDTH4 + FONT5X7 + displaylines)); //0x28, 0b101000
	bpDelayMS(15);//delay 15ms
	
	//Turn display off
	HD44780_WriteByte(HD44780_COMMAND, CMD_DISPLAYCONTROL + DISPLAYOFF + CURSEROFF + BLINKOFF);//0x08, 0b1000
	bpDelayMS(15);//delay 15ms
	
	//Clear LCD and return home
	HD44780_WriteByte(HD44780_COMMAND, CMD_CLEARDISPLAY);
	bpDelayMS(15);//delay 15ms
	
	//Turn on display, turn off cursor and blink
	HD44780_WriteByte(HD44780_COMMAND, CMD_DISPLAYCONTROL + DISPLAYON + CURSERON + BLINKOFF);   // 0x0f, 0b1111
	bpDelayMS(15);//delay 15ms
}

//reset LCD to 4bit mode
void HD44780_Reset(void){

	HD44780_I2Cwrite(0); //clear IO pins to HD44780
	//# Wait more than 15 msecs after power is applied.
	bpDelayMS(15);
	//# Write 0x03 to LCD and wait 5 msecs for the instruction to complete
	HD44780_WriteNibble(HD44780_COMMAND, 0x03);
	bpDelayMS(5);
	//# Write 0x03 to LCD and wait 160 usecs for instruction to complete
	HD44780_WriteNibble(HD44780_COMMAND, 0x03);
	bpDelayUS(160);
	//# Write 0x03 AGAIN to LCD and wait 160 usecs (or poll the Busy Flag) 
	HD44780_WriteNibble(HD44780_COMMAND, 0x03);
	bpDelayUS(160);
	//Set the Operating Characteristics of the LCD
    //* Write 0x02 to the LCD to Enable Four Bit Mode 
	HD44780_WriteNibble(HD44780_COMMAND, 0x02);
	bpDelayUS(160);
}

//write a string to the LCD
void HD44780_WriteString(char *s){
	char c;
	while((c = *s++)) HD44780_WriteByte(HD44780_DATA, c);
}

//write byte dat to register reg
void HD44780_WriteByte(unsigned char reg, unsigned char dat){
	HD44780_WriteNibble(reg, (dat>>4) );
	HD44780_WriteNibble(reg, (dat & 0x0F));
}

//read byte from LCD register reg
unsigned char HD44780_ReadByte(unsigned char reg){
	unsigned char dat;
	
	dat=(HD44780_ReadNibble(reg)<<4);
	dat|=HD44780_ReadNibble(reg);
	return dat;
}

//write 4 bits dat to register reg
void HD44780_WriteNibble(unsigned char reg, unsigned char dat){
	//EN pin should already be low
	//RW bit should be 0 (already 0 in dat)
	//LED bit should be 0 (already 0 in dat)
	//databits are aligned with the lower four bits of PCF8574, we can just use dat
	//rearrange if you use a different pinout

	if(reg==HD44780_DATA){	//does RS need to be set?
		dat |= PCF8574_LCD_RS; //set register select flag for text
	}//leave as 0 for a command

	HD44780_I2Cwrite(dat); //load values

	dat |= PCF8574_LCD_EN; //raise the EN line to clock in the values
	HD44780_I2Cwrite(dat);

	//optional setup delay

	dat &= (~PCF8574_LCD_EN); //lower EN line
	HD44780_I2Cwrite(dat);

}

//read 4 bits from register reg
unsigned char HD44780_ReadNibble(unsigned char reg){
	unsigned char dat=0, nibble=0;

	//EN pin should already be low
	dat |= PCF8574_LCD_RW;//RW bit should be 1 (already 0 in dat)
	//LED bit should be 0 (already 0 in dat)
	if(reg==HD44780_DATA){	//does RS need to be set?
		dat |= PCF8574_LCD_RS; //set register select flag for text
	}//leave as 0 for a command
	dat|=0b1111;//PCF8574 IO pins must be high for reads

	HD44780_I2Cwrite(dat); //load values
	dat |= PCF8574_LCD_EN; //raise the EN line to clock in the values
	HD44780_I2Cwrite(dat);

	//optional setup delay

	nibble=HD44780_I2Cread();//read datastate
	nibble&=(~0b11110000); //clear upper four bits

	dat &= (~PCF8574_LCD_EN); //lower EN line
	HD44780_I2Cwrite(dat);
	return nibble;
}

unsigned char HD44780_I2Cread(void){
	unsigned char c;

	i2cstart();
	i2csendbyte((PCF8574_ADDRESS_WRITE+1)); //read address is WR+1
	if(!i2cgetack()){bpWline("PCF8574 NO ACK, CHECK CONNECTION"); return 0;}
	c=i2cgetbyte();
	i2csendack();
	i2cstop();
	return c;
}

//write value to PCF8574 I2C IO expander, message and return on ACK error
void HD44780_I2Cwrite(unsigned char datout){
	i2cstart();
	i2csendbyte(PCF8574_ADDRESS_WRITE);
	if(!i2cgetack()){bpWline("PCF8574 NO ACK, CHECK CONNECTION"); return;}
	i2csendbyte(datout);
	if(!i2cgetack()){bpWline("PCF8574 NO ACK, CHECK CONNECTION"); return;}
	i2cstop();
}