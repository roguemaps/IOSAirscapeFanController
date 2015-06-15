//
//  WifiInfo.h
//  netScan
//
//  Created by Jesse Walter Vanderwerf on 11/4/14.
//  Copyright (c) 2014 Jesse Walter Vanderwerf. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface WifiInfo : NSObject

- (NSString *)getIPAddress:(BOOL)preferIPv4;

- (NSDictionary *)getIPAddresses;

- (NSString *)getBroadcastIp:(NSString*)localIPAddress;

- (NSString *)getMinIp:(NSString*)localIPAddress;

- (NSString *) getNetMask;

- (unsigned long)StrIp2UnsignedLong:(NSString *)ip;

- (unsigned int)StrIp2UnsignedInt:(NSString *)ip;

- (NSString *)unsignedInt2StrIp:(in_addr_t)ip;

- (NSString *)reverseString:(NSString *)str;

- (NSDictionary *)fetchSSIDInfo;
@end
