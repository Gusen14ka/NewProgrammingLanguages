#import <Foundation/Foundation.h>

@interface TextStats : NSObject {
    NSUInteger _lines;
    NSUInteger _words;
    NSString *_longestWord;
    NSUInteger _letters[26];
}
@property (nonatomic) NSUInteger lines;
@property (nonatomic) NSUInteger words;
@property (nonatomic, copy) NSString *longestWord;
- (void)analyze:(NSString *)text;
- (NSUInteger)countForLetter:(unichar)c;
@end

@implementation TextStats

@synthesize lines = _lines;
@synthesize words = _words;
@synthesize longestWord = _longestWord;

- (void)analyze:(NSString *)text {
    self.lines = 0;
    self.words = 0;
    self.longestWord = @"";
    memset(_letters, 0, sizeof(_letters));

    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        self.lines++;
        NSCharacterSet *separators = [[NSCharacterSet letterCharacterSet] invertedSet];
        for (NSString *word in [line componentsSeparatedByCharactersInSet:separators]) {
            if ([word length] == 0) continue;
            self.words++;
            if ([word length] > [self.longestWord length]) self.longestWord = word;
        }
    }
    if ([text hasSuffix:@"\n"]) self.lines--;

    NSString *lower = [text lowercaseString];
    for (NSUInteger i = 0; i < [lower length]; i++) {
        unichar c = [lower characterAtIndex:i];
        if (c >= 'a' && c <= 'z') _letters[c - 'a']++;
    }
}

- (NSUInteger)countForLetter:(unichar)c {
    return _letters[c - 'a'];
}

@end

static void printLine(NSString *s) {
    printf("%s\n", [s UTF8String]);
}

int main(int argc, const char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    {
        NSString *path;
        if (argc > 1) {
            path = [NSString stringWithUTF8String:argv[1]];
        } else {
            printf("Path to text file: ");
            char buf[1024];
            if (!fgets(buf, sizeof(buf), stdin)) return 1;
            path = [[NSString stringWithUTF8String:buf]
                    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }

        NSError *error = nil;
        NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
        if (!text) {
            printLine([NSString stringWithFormat:@"Cannot read file '%@'", path]);
            [pool drain];
            return 1;
        }

        TextStats *stats = [[TextStats alloc] init];
        [stats analyze:text];

        printLine([NSString stringWithFormat:@"File:         %@", path]);
        printLine([NSString stringWithFormat:@"Lines:        %lu", (unsigned long)stats.lines]);
        printLine([NSString stringWithFormat:@"Words:        %lu", (unsigned long)stats.words]);
        printLine([NSString stringWithFormat:@"Longest word: %@ (%lu letters)",
                   stats.longestWord, (unsigned long)[stats.longestWord length]]);

        unichar order[26];
        NSUInteger used = 0;
        for (unichar c = 'a'; c <= 'z'; c++) {
            if ([stats countForLetter:c] > 0) order[used++] = c;
        }
        for (NSUInteger i = 1; i < used; i++) {
            unichar cur = order[i];
            NSUInteger j = i;
            while (j > 0 && [stats countForLetter:order[j - 1]] < [stats countForLetter:cur]) {
                order[j] = order[j - 1];
                j--;
            }
            order[j] = cur;
        }

        printLine(@"\nLetter frequency (a-z):");
        for (NSUInteger i = 0; i < used; i++) {
            NSUInteger count = [stats countForLetter:order[i]];
            NSMutableString *bar = [NSMutableString string];
            for (NSUInteger k = 0; k < count && k < 50; k++) [bar appendString:@"#"];
            printLine([NSString stringWithFormat:@"  %c %5lu %@", (char)order[i], (unsigned long)count, bar]);
        }

        NSString *logPath = @"stats_log.txt";
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        [df setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        NSMutableString *freq = [NSMutableString string];
        for (NSUInteger i = 0; i < used; i++) {
            [freq appendFormat:@"%@%c=%lu", i ? @" " : @"", (char)order[i],
                               (unsigned long)[stats countForLetter:order[i]]];
        }
        NSString *entry = [NSString stringWithFormat:@"%@ | %@ | lines=%lu words=%lu longest=%@ | letters: %@\n",
                           [df stringFromDate:[NSDate date]], path,
                           (unsigned long)stats.lines, (unsigned long)stats.words, stats.longestWord, freq];

        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:logPath]) [fm createFileAtPath:logPath contents:nil attributes:nil];
        NSFileHandle *log = [NSFileHandle fileHandleForWritingAtPath:logPath];
        [log seekToEndOfFile];
        [log writeData:[entry dataUsingEncoding:NSUTF8StringEncoding]];
        [log closeFile];

        printLine([NSString stringWithFormat:@"\nAppended entry to %@", logPath]);
    }
    [pool drain];
    return 0;
}
