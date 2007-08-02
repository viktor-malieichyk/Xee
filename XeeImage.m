#import "XeeImage.h"

#import <pthread.h>


@implementation XeeImage

-(id)init
{
	if(self=[super init])
	{
		ref=nil;
		attrs=nil;
		filehandle=nil;

		nextselector=NULL;
		loaded=YES;
		thumbonly=stop=NO;

		format=nil;
		width=height=0;
		depth=nil;
		icon=depthicon=nil;
		transparent=NO;
		back=nil;

		orientation=XeeNoTransformation;
		correctorientation=XeeUnknownTransformation;
		crop_x=crop_y=0;
		crop_width=crop_height=0;

		delegate=nil;

		properties=[[NSMutableArray array] retain];
	}

	return self;
}

-(void)dealloc
{
	if(nextselector) [self endLoader];

	[ref release];
	[attrs release];
	[filehandle release];

	[format release];
	[depth release];
	[icon release];
	[depthicon release];
	[back release];

	[properties release];

	[super dealloc];
}



-(SEL)initLoader { return NULL; }

-(void)deallocLoader { }



-(BOOL)startLoaderForFile:(NSString *)name attributes:(NSDictionary *)attributes
{
	return [self startLoaderForRef:[XeeFSRef refForPath:name] attributes:attributes];
}

-(BOOL)startLoaderForRef:(XeeFSRef *)fsref attributes:(NSDictionary *)attributes
{
	ref=[fsref retain];
	attrs=[attributes retain];
	icon=[[[NSWorkspace sharedWorkspace] iconForFile:[ref path]] retain];
	[icon setSize:NSMakeSize(16,16)];

	nextselector=@selector(initLoader);
	stop=NO;
	loaded=NO;

	@try
	{
		do {
			NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
			nextselector=(SEL)[self performSelector:nextselector];
			[pool release];
		} while(nextselector&&!width&&!height);
	}
	@catch(id e)
	{
		NSLog(@"Exception during initial loading of \"%@\": %@",[self filename],e);
		nextselector=NULL;
	}

	if(!nextselector) [self endLoader];

	return nextselector!=NULL;
}

-(void)runLoader
{
	if(!nextselector) return;

	stop=NO;
	@try
	{
		do {
			NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
			nextselector=(SEL)[self performSelector:nextselector];
			[pool release];
		} while(nextselector&&!stop);
	}
	@catch(id e)
	{
		NSLog(@"Exception during loading of \"%@\": %@",[self filename],e);
		nextselector=NULL;
	}

	if(!nextselector)
	{
		[self endLoader];
		[self triggerChangeAction];
	}
}

-(void)runLoaderForThumbnail
{
	thumbonly=YES;
	[self runLoader];
}

-(void)endLoader
{
	[self deallocLoader];
	[filehandle release];
	filehandle=nil;
}



-(BOOL)loaded { return loaded; }

-(BOOL)failed { return nextselector==NULL&&!loaded; }

-(BOOL)needsLoading { return nextselector!=NULL; }

-(void)stopLoading { stop=YES; }

-(BOOL)hasBeenStopped { return stop; }

-(XeeFileHandle *)fileHandle
{
	if(!filehandle)
	{
		filehandle=[[XeeFileHandle fileHandleWithPath:[self filename]] retain];
		if(!filehandle) [NSException raise:@"XeeCouldNotOpenFileException" format:@"Failed to open file \"%@\".",[self filename]];
	}
	return filehandle;
}



-(int)frames { return 0; }

-(void)setFrame:(int)frame { }

-(int)frame { return 0; }



-(void)setDelegate:(id)newdelegate
{
	delegate=newdelegate;
}

#include <unistd.h>
-(void)triggerLoadingAction
{
	if(pthread_main_np()) [delegate xeeImageLoadingProgress:self];
	else [delegate performSelectorOnMainThread:@selector(xeeImageLoadingProgress:) withObject:self waitUntilDone:NO];
//	usleep(20000);
}

-(void)triggerChangeAction
{
	if(pthread_main_np()) [delegate xeeImageDidChange:self];
	else [delegate performSelectorOnMainThread:@selector(xeeImageDidChange:) withObject:self waitUntilDone:NO];
}

-(void)triggerSizeChangeAction
{
	if(pthread_main_np()) [delegate xeeImageSizeDidChange:self];
	else [delegate performSelectorOnMainThread:@selector(xeeImageSizeDidChange:) withObject:self waitUntilDone:NO];
}

-(void)triggerPropertyChangeAction
{
	if(pthread_main_np()) [delegate xeeImagePropertiesDidChange:self];
	else [delegate performSelectorOnMainThread:@selector(xeeImagePropertiesDidChange:) withObject:self waitUntilDone:NO];
}



-(BOOL)animated { return NO; }

-(void)setAnimating:(BOOL)animating { }

-(void)setAnimatingDefault { }

-(BOOL)animating { return NO; }



-(NSRect)updatedAreaInRect:(NSRect)rect { return NSMakeRect(0,0,0,0); }



-(void)drawInRect:(NSRect)rect bounds:(NSRect)bounds { [self drawInRect:rect bounds:bounds lowQuality:NO]; }

-(void)drawInRect:(NSRect)rect bounds:(NSRect)bounds lowQuality:(BOOL)lowquality {}



-(CGImageRef)createCGImage { return NULL; }

-(int)losslessSaveFlags { return 0; }

-(BOOL)losslessSaveTo:(NSString *)path flags:(int)flags { return NO; }



-(NSString *)filename { return [ref path]; }

-(NSString *)format { return format; }

-(NSImage *)icon { return icon; }

-(int)width
{
	if(XeeTransformationIsFlipped(orientation)) return crop_height?crop_height:height;
	else return crop_width?crop_width:width;
}

-(int)height
{
	if(XeeTransformationIsFlipped(orientation)) return crop_width?crop_width:width;
	else return crop_height?crop_height:height;
}

-(int)fullWidth
{
	if(XeeTransformationIsFlipped(orientation)) return height;
	else return width;
}

-(int)fullHeight
{
	if(XeeTransformationIsFlipped(orientation)) return width;
	else return height;
}

-(NSString *)depth { return depth; }

-(NSImage *)depthIcon { return depthicon; }

-(BOOL)transparent { return transparent; }

-(NSColor *)backgroundColor
{
	if(!back) back=[[NSUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] dataForKey:@"defaultImageBackground"]] retain];

	return back;
}

-(int)orientation { return orientation; }

-(int)correctOrientation { return correctorientation; }

-(NSRect)croppingRect
{
	return XeeTransformRect(XeeMatrixForTransformation(orientation,width,height),[self rawCroppingRect]);
}

-(NSRect)rawCroppingRect
{
	if(crop_width||crop_height) return NSMakeRect(crop_x,crop_y,crop_width,crop_height);
	else return NSMakeRect(0,0,width,height);
}

-(BOOL)isTransformed
{
	return XeeTransformationIsNonTrivial([self orientation])||[self isCropped];
}

-(BOOL)isCropped
{
	return [self width]!=[self fullWidth]||[self height]!=[self fullHeight];
}

-(XeeMatrix)transformationMatrix
{
	return XeeMultiplyMatrices(
		XeeMatrixForTransformation(orientation,crop_width?crop_width:width,crop_height?crop_height:height),
		XeeTranslationMatrix(-crop_x,-crop_y));
}

-(XeeMatrix)transformationMatrixInRect:(NSRect)rect
{
	return XeeMultiplyMatrices(
		XeeTransformRectToRectMatrix(NSMakeRect(0,0,[self width],[self height]),rect),
		[self transformationMatrix]);
}

-(NSArray *)properties
{
	NSMutableArray *proparray=[NSMutableArray array];

	[proparray addObject:[XeePropertyItem subSectionItemWithLabel:
	NSLocalizedString(@"Image properties",@"Image properties section title")
	labelsAndValues:
		NSLocalizedString(@"Image width:",@"Image width property label"),
		[NSNumber numberWithInt:[self width]],
		NSLocalizedString(@"Image height:",@"Image height property label"),
		[NSNumber numberWithInt:[self height]],
		NSLocalizedString(@"File format:",@"File format property label"),
		[self format],
		NSLocalizedString(@"Colour format:",@"Colour format property label"),
		[self depth],
	nil]];

	NSRect crop=[self croppingRect];
	if(crop.size.width!=[self fullWidth]||crop.size.height!=[self fullHeight])
	{
		[proparray addObject:[XeePropertyItem subSectionItemWithLabel:
		NSLocalizedString(@"Cropping properties",@"Cropping properties section title")
		labelsAndValues:
			NSLocalizedString(@"Full image width:",@"Full image width property label"),
			[NSNumber numberWithInt:[self fullWidth]],
			NSLocalizedString(@"Full image height:",@"Full image height property label"),
			[NSNumber numberWithInt:[self fullHeight]],
			NSLocalizedString(@"Cropping top:",@"Cropping top property label"),
			[NSNumber numberWithInt:crop.origin.y],
			NSLocalizedString(@"Cropping bottom:",@"Cropping bottom property label"),
			[NSNumber numberWithInt:[self fullHeight]-crop.size.height-crop.origin.y],
			NSLocalizedString(@"Cropping left:",@"Cropping left property label"),
			[NSNumber numberWithInt:crop.origin.x],
			NSLocalizedString(@"Cropping right:",@"Cropping right property label"),
			[NSNumber numberWithInt:[self fullWidth]-crop.size.width-crop.origin.x],
		nil]];
	}

	NSString *filename=[self filename];
	if(filename&&attrs)
	{
		XeePropertyItem *item;

		[proparray addObject:item=[XeePropertyItem subSectionItemWithLabel:
		NSLocalizedString(@"File properties",@"File properties section title")
		labelsAndValues:
			NSLocalizedString(@"File name:",@"File name property label"),
			[filename lastPathComponent],
			NSLocalizedString(@"Full path:",@"Full path property label"),
			filename,
			NSLocalizedString(@"File size:",@"File size property label"),//	55.92 kB (57264 bytes)
			[NSString stringWithFormat:
			NSLocalizedString(@"%@ (%d bytes)",@"File size property value (%@ is shortened filesize, %d is exact)"),
			[self descriptiveFileSize],[self fileSize]],
			NSLocalizedString(@"Modification date:",@"Modification date property label"),
			[[attrs fileModificationDate] descriptionWithCalendarFormat:@"%Y-%m-%d %H:%M" timeZone:nil locale:nil],
			NSLocalizedString(@"Creation date:",@"Creation date property label"),
			[[attrs fileCreationDate] descriptionWithCalendarFormat:@"%Y-%m-%d %H:%M" timeZone:nil locale:nil],
		nil]];

		NSMutableArray *fileprops=[item value];

		// Check for futaba timestamp name
		NSString *namepart=[[filename lastPathComponent] stringByDeletingPathExtension];
		int len=[namepart length];

		if(len==10||len==13||len==17)
		{
			BOOL matches=YES;
			for(int i=0;i<len;i++)
			{
				unichar c=[namepart characterAtIndex:i];
				if(i<13&&!(c>='0'||c<='9')) matches=NO;
				if(i>=13&&!((c>='0'&&c<='9')||(c>='a'||c<='f')||(c>='A'||c<='F'))) matches=NO;
			}

			if(matches)
			{
				int seconds=[[namepart substringToIndex:10] intValue];
				if(seconds>1000000000)
				{
					[fileprops addObject:[XeePropertyItem itemWithLabel:
					NSLocalizedString(@"Futaba timestamp:",@"Futaba timestamp property label")
					value:[[NSDate dateWithTimeIntervalSince1970:seconds] descriptionWithCalendarFormat:@"%Y-%m-%d %H:%M" timeZone:nil locale:nil]]];
				}
			}
		}
	}

	[proparray addObjectsFromArray:properties];

	return proparray;
}



-(int)fileSize { return [attrs fileSize]; }

-(NSString *)descriptiveFileSize
{
	int size=[self fileSize];
	if(size<10000) return [NSString stringWithFormat:
		NSLocalizedString(@"%d B",@"A file size in bytes"),size];
	else if(size<102400) return [NSString stringWithFormat:
		NSLocalizedString(@"%.2f kB",@"A file size in kilobytes with two decimals"),((float)size/1024.0)];
	else if(size<1024000) return [NSString stringWithFormat:
		NSLocalizedString(@"%.1f kB",@"A file size in kilobytes with one decimal"),((float)size/1024.0)];
	else return [NSString stringWithFormat:
		NSLocalizedString(@"%d kB",@"A file size in kilobytes with no decimals"),size/1024];
}

-(NSString *)descriptiveDate
{
	return [[attrs fileModificationDate] descriptionWithCalendarFormat:@"%Y-%m-%d %H:%M" timeZone:nil locale:nil];
}



-(void)setFormat:(NSString *)fmt { [format autorelease]; format=[fmt retain]; }

-(void)setBackgroundColor:(NSColor *)col { [back autorelease]; back=[col retain]; }

-(void)setOrientation:(XeeTransformation)transformation
{
	if(transformation==orientation) return;

	BOOL sizechanged=XeeTransformationIsFlipped(orientation)!=XeeTransformationIsFlipped(transformation);

	orientation=transformation;

	if(sizechanged) [self triggerSizeChangeAction];
	else [self triggerChangeAction];
	[self triggerPropertyChangeAction];
}

-(void)setCorrectOrientation:(XeeTransformation)transformation
{
	correctorientation=transformation;

	if(correctorientation)
	if([[NSUserDefaults standardUserDefaults] boolForKey:@"useOrientation"])
	orientation=correctorientation;
}

-(void)setCroppingRect:(NSRect)rect
{
//	XeeMatrix inv=XeeInverseMatrix([self transformationMatrix]);
	XeeMatrix inv=XeeInverseMatrix(XeeMatrixForTransformation(orientation,width,height));

	NSRect newcrop=XeeTransformRect(inv,rect);
	if(newcrop.size.width==width&&newcrop.size.height==height)
	{
		crop_x=crop_y=0;
		crop_width=crop_height=0;
	}
	else
	{
		crop_x=newcrop.origin.x;
		crop_y=newcrop.origin.y;
		crop_width=newcrop.size.width;
		crop_height=newcrop.size.height;
	}
	[self triggerSizeChangeAction];
	[self triggerPropertyChangeAction];
}

-(void)resetTransformations
{
	if([[NSUserDefaults standardUserDefaults] boolForKey:@"useOrientation"]) orientation=correctorientation;	
	else orientation=XeeNoTransformation;

	crop_x=crop_y=0;
	crop_width=crop_height=0;

	[self triggerSizeChangeAction];
	[self triggerPropertyChangeAction];
}




-(void)setDepth:(NSString *)d { [depth autorelease]; depth=[d retain]; }

-(void)setDepthIcon:(NSImage *)newicon { [depthicon autorelease]; depthicon=[newicon retain]; }

-(void)setDepthIconName:(NSString *)iconname { [self setDepthIcon:[NSImage imageNamed:iconname]]; }

-(void)setDepth:(NSString *)d iconName:(NSString *)iconname { [self setDepth:d]; [self setDepthIconName:iconname]; }

-(void)setDepthBitmap
{
	[self setDepth:NSLocalizedString(@"Bitmap",@"Description for 1-bit bitmapped images")
	iconName:@"depth_bitmap"];
}

-(void)setDepthIndexed:(int)colors
{
	[self setDepth:
	[NSString stringWithFormat:NSLocalizedString(@"%d colours",@"Description for indexed-colour images"),colors]
	iconName:@"depth_indexed"]; // needs alpha!
}

-(void)setDepthGrey:(int)bits alpha:(BOOL)alpha floating:(BOOL)floating
{
	if(floating&&alpha) [self setDepth:
		[NSString stringWithFormat:NSLocalizedString(@"%d bits FP grey+alpha",@"Description for floating-point grey+alpha images"),bits]
		iconName:@"depth_greyalpha"];
	else if(floating) [self setDepth:
		[NSString stringWithFormat:NSLocalizedString(@"%d bits FP grey",@"Description for floating-point greyscale images"),bits]
		iconName:@"depth_grey"];
	else if(alpha) [self setDepth:
		[NSString stringWithFormat:NSLocalizedString(@"%d bits grey+alpha",@"Description for grey+alpha images"),bits]
		iconName:@"depth_greyalpha"];
	else [self setDepth:
		[NSString stringWithFormat:NSLocalizedString(@"%d bits grey",@"Description for greyscale images"),bits]
		iconName:@"depth_grey"];
}

-(void)setDepthRGB:(int)bits alpha:(BOOL)alpha floating:(BOOL)floating
{
	if(floating&&alpha) [self setDepth:
		[NSString stringWithFormat:NSLocalizedString(@"%d bits FP RGBA",@"Description for floating-point RGBA images"),bits]
		iconName:@"depth_rgba"];
	else if(floating) [self setDepth:
		[NSString stringWithFormat:NSLocalizedString(@"%d bits FP RGB",@"Description for floating-point RGB images"),bits]
		iconName:@"depth_rgb"];
	else if(alpha) [self setDepth:
		[NSString stringWithFormat:NSLocalizedString(@"%d bits RGBA",@"Description for RGBA images"),bits]
		iconName:@"depth_rgba"];
	else [self setDepth:
		[NSString stringWithFormat:NSLocalizedString(@"%d bits RGB",@"Description for RGBA images"),bits]
		iconName:@"depth_rgb"];
}

-(void)setDepthCMYK:(int)bits alpha:(BOOL)alpha
{
	if(alpha) [self setDepth:
		[NSString stringWithFormat:NSLocalizedString(@"%d bits CMYK+alpha",@"Description for CMYK+alpha images"),bits]
		iconName:@"depth_cmyk"];
	else [self setDepth:
		[NSString stringWithFormat:NSLocalizedString(@"%d bits CMYK",@"Description for CMYK images"),bits]
		iconName:@"depth_cmyk"];
}

-(void)setDepthLab:(int)bits alpha:(BOOL)alpha
{
	if(alpha) [self setDepth:
		[NSString stringWithFormat:NSLocalizedString(@"%d bits Lab+alpha",@"Description for Lab+alpha images"),bits]
		iconName:@"depth_rgb"];
	else [self setDepth:
		[NSString stringWithFormat:NSLocalizedString(@"%d bits Lab",@"Description for Lab images"),bits]
		iconName:@"depth_rgb"];
}

-(void)setDepthGrey:(int)bits { [self setDepthGrey:bits alpha:NO floating:NO]; }

-(void)setDepthRGB:(int)bits { [self setDepthRGB:bits alpha:NO floating:NO]; }

-(void)setDepthRGBA:(int)bits { [self setDepthRGB:bits alpha:YES floating:NO]; }




-(id)description
{
	return [NSString stringWithFormat:@"<%@> %@ (%dx%d %@ %@, %@, created on %@)",
	[[self class] description],[[self filename] lastPathComponent],[self width],[self height],
	[self depth],[self format],[self descriptiveFileSize],[self descriptiveDate]];
}




NSMutableArray *imageclasses=nil;


+(XeeImage *)imageForFilename:(NSString *)filename
{
	XeeFSRef *ref=[XeeFSRef refForPath:filename];
	if(ref) return [self imageForRef:ref];
	return nil;
}

+(XeeImage *)imageForRef:(XeeFSRef *)ref
{
	if(!imageclasses) return nil;

	NSString *filename=[ref path];

	NSDictionary *attrs=[[NSFileManager defaultManager] fileAttributesAtPath:filename traverseLink:YES];
	if(!attrs) return nil;

	NSFileHandle *file=[NSFileHandle fileHandleForReadingAtPath:filename];
	if(!file) return nil;

	NSData *block=[file readDataOfLength:512];
	if(!block) return nil;

	[file closeFile];

	NSEnumerator *enumerator=[imageclasses objectEnumerator];
	Class class;
	while(class=[enumerator nextObject])
	{
		if([class canOpenFile:filename firstBlock:block attributes:attrs])
		{
			XeeImage *image=[[class alloc] init];
			if(image)
			{
				if([image startLoaderForRef:ref attributes:attrs])
				{
					return [image autorelease];
				}
				[image release];
			}
		}
	}

	return nil;
}

+(NSArray *)allFileTypes
{
	if(!imageclasses) return nil;

	NSMutableArray *types=[NSMutableArray array];
	NSEnumerator *enumerator=[imageclasses objectEnumerator];
	Class class;

	while(class=[enumerator nextObject])
	{
		NSEnumerator *typeenum=[[class fileTypes] objectEnumerator];
		NSString *type;
		while(type=[typeenum nextObject]) if(![types containsObject:type]) [types addObject:type];
	}

	return types;
}

+(void)registerImageClass:(Class)class
{
	if(!imageclasses) imageclasses=[[NSMutableArray array] retain];

	[imageclasses addObject:class];
}



+(BOOL)canOpenFile:(NSString *)name firstBlock:(NSData *)block attributes:(NSDictionary *)attributes
{
	return NO;
}

+(NSArray *)fileTypes { return nil; }

@end



@implementation NSObject (XeeImageDelegate)

-(void)xeeImageLoadingProgress:(XeeImage *)image {}
-(void)xeeImageDidChange:(XeeImage *)image {}
-(void)xeeImageSizeDidChange:(XeeImage *)image {}
-(void)xeeImagePropertiesDidChange:(XeeImage *)image {}

@end



@implementation XeePropertyItem

-(id)initWithLabel:(NSString *)itemlabel value:(id)itemvalue
{
	if(self=[super init])
	{
		label=[itemlabel retain];
		value=[itemvalue retain];
	}
	return self;
}

-(void)dealloc
{
	[label release];
	[value release];
	[super dealloc];
}

-(NSString *)label { return label; }
-(id)value { return value; }
-(BOOL)isSubSection { return [value isKindOfClass:[NSArray class]]; }

-(BOOL)isEqual:(XeePropertyItem *)other
{
	return [label caseInsensitiveCompare:[other label]]==NSOrderedSame&&[value isEqual:[other value]];
}

-(NSComparisonResult)compare:(XeePropertyItem *)other
{
	return [label caseInsensitiveCompare:[other label]];
}

+(XeePropertyItem *)itemWithLabel:(NSString *)itemlabel value:(id)itemvalue
{
	return [[[self alloc] initWithLabel:itemlabel value:itemvalue] autorelease];
}

+(XeePropertyItem *)subSectionItemWithLabel:(NSString *)itemlabel labelsAndValues:(id)first,...
{
	NSMutableArray *array=[NSMutableArray array];
	XeePropertyItem *item=[[[self alloc] initWithLabel:itemlabel value:array] autorelease];

	va_list va;
	va_start(va,first);
	for(;;)
	{
		NSString *label=first?first:va_arg(va,NSString *);
		id value=va_arg(va,id);

		if(!label||!value) break;

		XeePropertyItem *subitem=[[self alloc] initWithLabel:label value:value];
		[array addObject:subitem];
		[subitem release];

		first=nil;
	}
	va_end(va);

	return item;
}

@end