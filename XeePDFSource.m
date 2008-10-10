#import "XeePDFSource.h"
#import "PDFParser.h"
#import "XeeRawImage.h"
#import "XeeIndexedRawImage.h"
#import "XeeJPEGLoader.h"
#import "XeeImageIOLoader.h"


static int XeePDFSortPages(id first,id second,void *context)
{
	NSDictionary *order=(NSDictionary *)context;
	NSNumber *firstpage=[order objectForKey:[first reference]];
	NSNumber *secondpage=[order objectForKey:[second reference]];
	if(!firstpage&&!secondpage) return 0;
	else if(!firstpage) return 1;
	else if(!secondpage) return -1;
	else return [firstpage compare:secondpage];
}

@implementation XeePDFSource

+(NSArray *)fileTypes
{
	return [NSArray arrayWithObject:@"pdf"];
}

-(id)initWithFile:(NSString *)pdfname
{
	if(self=[super init])
	{
		filename=[pdfname retain];
		@try
		{
			parser=[[PDFParser parserForPath:filename] retain];

			if([parser needsPassword]) @throw @"PDF file needs password";

			// Find image objects in object list
			NSMutableArray *images=[NSMutableArray array];
			NSEnumerator *enumerator=[[parser objectDictionary] objectEnumerator];
			id object;
			while(object=[enumerator nextObject])
			{
				if([object isKindOfClass:[PDFStream class]]&&[object isImage])
				[images addObject:object];
			}

			// Traverse page tree to find which images are referenced from which pages
			NSMutableDictionary *order=[NSMutableDictionary dictionary];
			NSDictionary *root=[parser pagesRoot];
			NSMutableArray *stack=[NSMutableArray arrayWithObject:[[root arrayForKey:@"Kids"] objectEnumerator]];
			int page=0;
			while([stack count])
			{
				id curr=[[stack lastObject] nextObject];
				if(!curr) [stack removeLastObject];
				else
				{
					NSString *type=[curr objectForKey:@"Type"];
					if([type isEqual:@"Pages"])
					{
						[stack addObject:[[curr arrayForKey:@"Kids"] objectEnumerator]];
					}
					else if([type isEqual:@"Page"])
					{
						page++;
						NSDictionary *xobjects=[[curr objectForKey:@"Resources"] objectForKey:@"XObject"];
						NSEnumerator *enumerator=[xobjects objectEnumerator];
						id object;
						while(object=[enumerator nextObject])
						{
							if([object isKindOfClass:[PDFStream class]]&&[object isImage])
							[order setObject:[NSNumber numberWithInt:page] forKey:[object reference]];
						}
					}
					else @throw @"Invalid PDF structure";
				}
			}

			// Sort image in page order
			[images sortUsingFunction:XeePDFSortPages context:order];

			[self startListUpdates];

			enumerator=[images objectEnumerator];
			PDFStream *image;
			while(image=[enumerator nextObject])
			{
				PDFObjectReference *ref=[image reference];
				NSNumber *page=[order objectForKey:ref];
				NSString *name;
				if(page) name=[NSString stringWithFormat:@"Page %@, object %d",page,[ref number]];
				else name=[NSString stringWithFormat:@"Object %d",[ref number]];

				[self addEntry:[[[XeePDFEntry alloc] initWithPDFStream:image name:name] autorelease]];
			}

			[self endListUpdates];

			[self setIcon:[[NSWorkspace sharedWorkspace] iconForFile:filename]];
			[icon setSize:NSMakeSize(16,16)];

			[self pickImageAtIndex:0];
		}
		@catch(id e)
		{
			if(![e isKindOfClass:[NSException class]]||![[e name] isEqual:PDFWrongMagicException])
			NSLog(@"Error parsing PDF file %@: %@",filename,e);
			[self release];
			return nil;
		}
	}
	return self;

}

-(void)dealloc
{
	[parser release];
	[filename release];
	[super dealloc];
}

-(NSString *)representedFilename { return filename; }

-(int)capabilities { return XeeNavigationCapable; }

@end




@implementation XeePDFEntry

-(id)initWithPDFStream:(PDFStream *)stream name:(NSString *)descname
{
	if(self=[super init])
	{
		object=[stream retain];
		name=[descname retain];
		complained=NO;
	}
	return self;
}

-(void)dealloc
{
	[object release];
	[name release];
	[super dealloc];
}

-(NSString *)descriptiveName { return name; }

-(XeeImage *)produceImage
{
	NSDictionary *dict=[object dictionary];
	XeeImage *newimage=nil;
	NSString *colourspace=[object colourSpaceOrAlternate];
	int bpc=[object bitsPerComponent];

	if([object isJPEG]&&bpc==8)
	{
		CSHandle *subhandle=[object JPEGHandle];
		if(subhandle) newimage=[[[XeeJPEGImage alloc] initWithHandle:subhandle] autorelease];
	}
	else if([object isTIFF])
	{
		CSHandle *subhandle=[object TIFFHandle];
		if(subhandle) newimage=[[[XeeImageIOImage alloc] initWithHandle:subhandle] autorelease];
	}
	else if([colourspace isEqual:@"DeviceGray"]||[colourspace isEqual:@"CalGray"])
	{
		CSHandle *subhandle=[object handle];
		if(subhandle)
		if(bpc==8) newimage=[[[XeeRawImage alloc] initWithHandle:subhandle
		width:[[dict objectForKey:@"Width"] intValue] height:[[dict objectForKey:@"Height"] intValue]
		depth:bpc colourSpace:XeeGreyRawColourSpace flags:XeeNoAlphaRawFlag] autorelease];
		[newimage setDepthGrey:bpc];
		//[newimage setFormat:@"Raw greyscale // TODO - add format names
	}
	else if([colourspace isEqual:@"DeviceRGB"]||[colourspace isEqual:@"CalRGB"])
	{
		CSHandle *subhandle=[object handle];
		if(subhandle)
		if(bpc==8) newimage=[[[XeeRawImage alloc] initWithHandle:subhandle
		width:[[dict objectForKey:@"Width"] intValue] height:[[dict objectForKey:@"Height"] intValue]
		depth:bpc colourSpace:XeeRGBRawColourSpace flags:XeeNoAlphaRawFlag] autorelease];
		[newimage setDepthRGB:bpc];
	}
	else if([colourspace isEqual:@"DeviceCMYK"]||[colourspace isEqual:@"CalCMYK"])
	{
		CSHandle *subhandle=[object handle];
		if(subhandle)
		if(bpc==8) newimage=[[[XeeRawImage alloc] initWithHandle:subhandle
		width:[[dict objectForKey:@"Width"] intValue] height:[[dict objectForKey:@"Height"] intValue]
		depth:bpc colourSpace:XeeCMYKRawColourSpace flags:XeeNoAlphaRawFlag] autorelease];
		[newimage setDepthCMYK:bpc alpha:NO];
	}
	else if([colourspace isEqual:@"DeviceLab"]||[colourspace isEqual:@"Callab"])
	{
		CSHandle *subhandle=[object handle];
		if(subhandle)
		if(bpc==8) newimage=[[[XeeRawImage alloc] initWithHandle:subhandle
		width:[[dict objectForKey:@"Width"] intValue] height:[[dict objectForKey:@"Height"] intValue]
		depth:bpc colourSpace:XeeLabRawColourSpace flags:XeeNoAlphaRawFlag] autorelease];
		[newimage setDepthLab:bpc alpha:NO];
	}
	else if([colourspace isEqual:@"Indexed"])
	{
		NSString *subcolourspace=[object subColourSpaceOrAlternate];
		if([subcolourspace isEqual:@"DeviceRGB"]||[subcolourspace isEqual:@"CalRGB"])
		{
			int colours=[object numberOfColours];
			NSData *palettedata=[object paletteData];

			if(palettedata)
			{
				const uint8 *palettebytes=[palettedata bytes];
				int count=[palettedata length]/3;
				if(count>256) count=256;

				XeePalette *pal=[XeePalette palette];
				for(int i=0;i<count;i++)
				[pal setColourAtIndex:i red:palettebytes[3*i] green:palettebytes[3*i+1] blue:palettebytes[3*i+2]];

				int subwidth=[[dict objectForKey:@"Width"] intValue];
				int subheight=[[dict objectForKey:@"Height"] intValue];
				CSHandle *subhandle=[object handle];

				if(subhandle) newimage=[[[XeeIndexedRawImage alloc] initWithHandle:subhandle width:subwidth height:subheight palette:pal] autorelease];
				[newimage setDepthIndexed:colours];
			}
		}
	}

	if(!newimage&&!complained)
	{
		NSLog(@"Unsupported image in PDF: ColorSpace=%@, BitsPerComponent=%@, Filter=%@, DecodeParms=%@",
		[dict objectForKey:@"ColorSpace"],[dict objectForKey:@"BitsPerComponent"],[dict objectForKey:@"Filter"],[dict objectForKey:@"DecodeParms"]);
		complained=YES;
	}

	return newimage;
}


@end