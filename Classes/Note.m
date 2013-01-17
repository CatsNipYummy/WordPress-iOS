//
//  Note.m
//  WordPress
//
//  Created by Beau Collins on 11/18/12.
//  Copyright (c) 2012 WordPress. All rights reserved.
//

#import "Note.h"
#import "AFImageRequestOperation.h"
#import "NSString+Helpers.h"
#import "JSONKit.h"

@interface XMLParserCollecter : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) NSMutableString *result;
@end
@implementation XMLParserCollecter

- (id)init {
    if (self = [super init]) {
        self.result = [[NSMutableString alloc] init];
    }
    return self;
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    [self.result appendString:string];
}

@end

@interface Note ()
@property (nonatomic, strong) NSDictionary *noteData;
@property (nonatomic, strong) AFImageRequestOperation *operation;
@property (readwrite, nonatomic, strong) NSString *commentText;

@end

@implementation Note

@dynamic timestamp;
@dynamic type;
@dynamic subject;
@dynamic payload;
@dynamic unread;
@dynamic icon;
@dynamic noteID;
@synthesize noteIconImage = _noteIconImage, operation, commentText = _commentText, noteData = _noteData;


+ (BOOL)syncNotesWithResponse:(NSArray *)notesData withManagedObjectContext:(NSManagedObjectContext *)context {
    
    [notesData enumerateObjectsUsingBlock:^(id noteData, NSUInteger idx, BOOL *stop) {
        [self createOrUpdateNoteWithData:noteData withManagedObjectContext:context];
    }];
    
    NSError *error;
    if(![context save:&error]){
        NSLog(@"Failed to sync notes: %@", error);
        return NO;
    } else {
        return YES;
    }
    
    
}

+ (void)createOrUpdateNoteWithData:(NSDictionary *)noteData withManagedObjectContext:(NSManagedObjectContext *)context {
    
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Note"];
    request.predicate = [NSPredicate predicateWithFormat:@"noteID = %@", [noteData objectForKey:@"id"]];
    request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"timestamp" ascending:NO]];
    request.fetchLimit = 1;
    
    NSError *error;
    NSArray *results = [context executeFetchRequest:request error:&error];
    if(error != nil){
        NSLog(@"Error finding note: %@", error);
        return;
    }
    Note *note;
    if ([results count] > 0) { // find a note so just update it
        note = (Note *)[results objectAtIndex:0];
    } else {
        note = (Note *)[NSEntityDescription insertNewObjectForEntityForName:@"Note"
                                                     inManagedObjectContext:context];
        
        note.noteID = [noteData objectForKey:@"id"];
    }
    
    note.payload = [noteData JSONData];
    note.type = [noteData objectForKey:@"type"];
    NSString *subject = [[noteData objectForKey:@"subject"] objectForKey:@"text"];
    note.subject = [subject trim];
    note.icon = [[noteData objectForKey:@"subject"] objectForKey:@"icon"];
    NSInteger timestamp = [[noteData objectForKey:@"timestamp"] integerValue];
    note.timestamp = [NSNumber numberWithInteger:timestamp];
    NSInteger unread = [[noteData objectForKey:@"unread"] integerValue];
    note.unread = [NSNumber numberWithInteger:unread];

}

- (void)dealloc {
    [self.operation cancel];
}

- (BOOL)isComment {
    return [self.type isEqualToString:@"comment"];
}

- (BOOL)isFollow {
    return [self.type isEqualToString:@"follow"];
}

- (BOOL)isLike {
    return [self.type isEqualToString:@"like"];
}

- (BOOL)isUnread {
    return [self.unread boolValue];
}

- (BOOL)isRead {
    return ![self isUnread];
}

- (NSString *)commentText {
    if (_commentText == nil) {
        [self parseComment];
    }
    return _commentText;
}

- (id)noteData {
    if (_noteData == nil) {
        _noteData = [self.payload objectFromJSONData];
    }
    return _noteData;
}

#pragma mark - Icon image loading

- (UIImage *)noteIconImage {
    if (_noteIconImage == nil) {
        [self loadImage];
        return [UIImage imageNamed:@"note_icon_placeholder"];
    }
    return _noteIconImage;
}

/*
 * TODO: image caching to disk?
 */
- (void)loadImage {
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:self.icon]];
    if (self.operation != nil) {
        [self.operation cancel];
    }
    self.operation = [AFImageRequestOperation imageRequestOperationWithRequest:request success:^(UIImage *image) {
        self.noteIconImage = image;
    }];
    [self.operation start];
}

#pragma mark - Comment HTML parsing

/*
 * Strips HTML Tags and converts html entites
 */
- (void)parseComment {
    
    if ([self isComment]) {
        NSDictionary *bodyItem = [[[self.noteData objectForKey:@"body"] objectForKey:@"items"] lastObject];
        NSString *comment = [bodyItem objectForKey:@"html"];
        comment = [comment stringByStrippingHTML];
        
        NSString *xmlString = [NSString stringWithFormat:@"<d>%@</d>", comment];
        NSData *xml = [xmlString dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
        NSXMLParser *parser = [[NSXMLParser alloc] initWithData:xml];
        XMLParserCollecter *collector = [[XMLParserCollecter alloc] init];
        parser.delegate = collector;
        [parser parse];
        
        self.commentText = collector.result;
        
    }
    
}

@end