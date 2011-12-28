//
//  FSURLOperation.m
//
//  Created by Christopher Miller on 10/31/11.
//  Copyright (c) 2011 Christopher Miller. All rights reserved.
//

#import "FSURLOperation.h"

enum FSURLOperationState {
    ready,
    executing,
    cancelled,
    finished
    } FSURLOperationState;

@interface FSURLOperation ()

@property (readwrite, assign) enum FSURLOperationState state;
@property (readwrite, retain) NSURLConnection* connection;
@property (readwrite, retain) NSSet* runLoopModes;
@property (readwrite, retain) NSMutableData* dataAccumulator;

+ (NSThread*)networkRequestThread;
- (void)finish;

@end

@implementation FSURLOperation

@synthesize request;
@synthesize response;
@synthesize payload;
@synthesize error;

@synthesize state;
@synthesize connection;
@synthesize runLoopModes;
@synthesize dataAccumulator;
@synthesize targetThread;
@synthesize onFinish;

+ (FSURLOperation*)URLOperationWithRequest:(NSURLRequest*)req
                           completionBlock:(void(^)(NSHTTPURLResponse* resp, NSData* payload, NSError* error))completion
{
    FSURLOperation* operation = [[self alloc] initWithRequest:req];
    operation.onFinish = completion;
    operation.targetThread = [self networkRequestThread];
    return operation;
}

+ (FSURLOperation*)URLOperationWithRequest:(NSURLRequest*)req
                           completionBlock:(void(^)(NSHTTPURLResponse* resp, NSData* payload, NSError* error))completion
                                  onThread:(NSThread*)thread
{
    FSURLOperation* operation = [[self alloc] initWithRequest:req];
    operation.onFinish = completion;
    if (thread)
        operation.targetThread = thread;
    else
        operation.targetThread = [self networkRequestThread];
    
    return operation;
}

+ (void)networkRequestThreadEntryPoint:(id)__unused object
{
    do {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] run];
        }
    } while (YES) ;
}

+ (NSThread*)networkRequestThread
{
    static NSThread* networkReqThread = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        networkReqThread = [[NSThread alloc] initWithTarget:self selector:@selector(networkRequestThreadEntryPoint:) object:nil];
        [networkReqThread setName:@"net.fsdev.FSURLOperation-Work-Thread"];
        [networkReqThread start];
    });
    
    return networkReqThread;
}

- (id)initWithRequest:(NSURLRequest *)_request
{
    self = [super init];
    if (self) {
        request = _request;
        self.runLoopModes = [NSSet setWithObject:NSRunLoopCommonModes];
    }
    return self;
}

- (void)finish
{
    [self willChangeValueForKey:@"isFinished"];
    self.state = finished;
    self.onFinish(self.response, self.payload, self.error);
    [self didChangeValueForKey:@"isFinished"];
}

- (void)operationDidStart
{
    if ([self isCancelled]) {
        [self finish];
        return;
    }
    
    self.connection = [[NSURLConnection alloc] initWithRequest:self.request delegate:self startImmediately:NO];
    
    NSRunLoop* runLoop = [NSRunLoop currentRunLoop];
    for (NSString* runLoopMode in self.runLoopModes) {
        [self.connection scheduleInRunLoop:runLoop forMode:runLoopMode];
    }
    
    [self.connection start];
}

- (void)startOnThread:(NSThread*)thread
{
    if (![self isReady])
        return;
    
    self.state = executing;
    
    [self performSelector:@selector(operationDidStart) onThread:thread withObject:nil waitUntilDone:YES modes:[self.runLoopModes allObjects]];
}

#pragma mark NSOperation

- (void)start
{
    if (![self isReady])
        return;
    
    self.state = executing;
    
    [self performSelector:@selector(operationDidStart) onThread:self.targetThread withObject:nil waitUntilDone:YES modes:[self.runLoopModes allObjects]];
}

- (BOOL)isConcurrent
{
    return YES;
}

- (BOOL)isExecuting
{
    return self.state == executing;
}

- (BOOL)isFinished
{
    return self.state == finished;
}

#pragma mark NSURLConnectionDelegate

- (void)       connection:(NSURLConnection*)connection
          didSendBodyData:(NSInteger)bytesWritten
        totalBytesWritten:(NSInteger)totalBytesWritten
totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite
{
    
}

- (void)connection:(NSURLConnection*)__unused conn
didReceiveResponse:(NSURLResponse *)resp
{
    self.response = (NSHTTPURLResponse*)resp;
    
    NSUInteger maxCapacity = MAX((NSUInteger)llabs(response.expectedContentLength), 1024);
    NSUInteger capacity = MIN(maxCapacity, 1024 * 1024 * 8);
    
    self.dataAccumulator = [NSMutableData dataWithCapacity:capacity];
}

- (void)connection:(NSURLConnection*)__unused conn
    didReceiveData:(NSData*)data
{
    [self.dataAccumulator appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection*)__unused conn
{
    self.payload = [NSData dataWithData:self.dataAccumulator];
    dataAccumulator = nil;
    
    [self finish];
}

- (void)connection:(NSURLConnection*)__unused conn
  didFailWithError:(NSError *)err
{
    self.error = err;
    
    self.dataAccumulator = nil;
    
    [self finish];
}

@end