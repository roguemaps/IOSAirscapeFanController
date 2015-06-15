//
//  WifiInfo.m
//  netScan
//
//  Created by Jesse Walter Vanderwerf on 11/4/14.
//  Copyright (c) 2014 Jesse Walter Vanderwerf. All rights reserved.
//

#import "WifiInfo.h"

#include <ifaddrs.h>
#include <arpa/inet.h>
#include <net/if.h>

@import SystemConfiguration.CaptiveNetwork;
@implementation WifiInfo


#define IOS_CELLULAR    @"pdp_ip0"
#define IOS_WIFI        @"en0"
#define IP_ADDR_IPv4    @"ipv4"
#define IP_ADDR_IPv6    @"ipv6"

- (NSString *)getIPAddress:(BOOL)preferIPv4
{
    NSArray *searchArray = preferIPv4 ?
    @[ IOS_WIFI @"/" IP_ADDR_IPv4, IOS_WIFI @"/" IP_ADDR_IPv6, IOS_CELLULAR @"/" IP_ADDR_IPv4, IOS_CELLULAR @"/" IP_ADDR_IPv6 ] :
    @[ IOS_WIFI @"/" IP_ADDR_IPv6, IOS_WIFI @"/" IP_ADDR_IPv4, IOS_CELLULAR @"/" IP_ADDR_IPv6, IOS_CELLULAR @"/" IP_ADDR_IPv4 ] ;
    
    NSDictionary *addresses = [self getIPAddresses];
    //NSLog(@"addresses: %@", addresses);
    
    __block NSString *address;
    [searchArray enumerateObjectsUsingBlock:^(NSString *key, NSUInteger idx, BOOL *stop)
     {
         address = addresses[key];
         if(address) *stop = YES;
     } ];
    return address ? address : @"0.0.0.0";
}

- (NSDictionary *)getIPAddresses
{
    NSMutableDictionary *addresses = [NSMutableDictionary dictionaryWithCapacity:8];
    
    // retrieve the current interfaces - returns 0 on success
    struct ifaddrs *interfaces;
    if(!getifaddrs(&interfaces)) {
        // Loop through linked list of interfaces
        struct ifaddrs *interface;
        for(interface=interfaces; interface; interface=interface->ifa_next) {
            if(!(interface->ifa_flags & IFF_UP) /* || (interface->ifa_flags & IFF_LOOPBACK) */ ) {
                continue; // deeply nested code harder to read
            }
            const struct sockaddr_in *addr = (const struct sockaddr_in*)interface->ifa_addr;
            char addrBuf[ MAX(INET_ADDRSTRLEN, INET6_ADDRSTRLEN) ];
            if(addr && (addr->sin_family==AF_INET || addr->sin_family==AF_INET6)) {
                NSString *name = [NSString stringWithUTF8String:interface->ifa_name];
                NSString *type;
                if(addr->sin_family == AF_INET) {
                    if(inet_ntop(AF_INET, &addr->sin_addr, addrBuf, INET_ADDRSTRLEN)) {
                        type = IP_ADDR_IPv4;
                    }
                } else {
                    const struct sockaddr_in6 *addr6 = (const struct sockaddr_in6*)interface->ifa_addr;
                    if(inet_ntop(AF_INET6, &addr6->sin6_addr, addrBuf, INET6_ADDRSTRLEN)) {
                        type = IP_ADDR_IPv6;
                    }
                }
                if(type) {
                    NSString *key = [NSString stringWithFormat:@"%@/%@", name, type];
                    addresses[key] = [NSString stringWithUTF8String:addrBuf];
                }
            }
        }
        // Free memory
        freeifaddrs(interfaces);
    }
    return [addresses count] ? addresses : nil;
}

- (NSString *)getBroadcastIp:(NSString*)localIPAddress {
    //retrieve the netmask from phone.
    NSString *netmaskAddress = [self getNetMask];

    // Strings to in_addr:
    struct in_addr localAddr;
    struct in_addr netmaskAddr;
    inet_aton([localIPAddress UTF8String], &localAddr);
    inet_aton([netmaskAddress UTF8String], &netmaskAddr);

    // The broadcast address calculation:
    localAddr.s_addr |= ~(netmaskAddr.s_addr);
    
    // in_addr to string:
    NSString *broadCastAddress = [NSString stringWithUTF8String:inet_ntoa(localAddr)];
    return broadCastAddress;
}

- (NSString *)getMinIp:(NSString*)localIPAddress {
    //retrieve the netmask from phone.
    NSString *netmaskAddress = [self getNetMask];
    
    // Strings to in_addr:
    struct in_addr localAddr;
    struct in_addr netmaskAddr;
    inet_aton([localIPAddress UTF8String], &localAddr);
    inet_aton([netmaskAddress UTF8String], &netmaskAddr);
    
    // The broadcast address calculation:
    localAddr.s_addr &= netmaskAddr.s_addr;
    // in_addr to string:
    NSString *minAddress = [NSString stringWithUTF8String:inet_ntoa(localAddr)];
    return minAddress;
}

/** Returns first non-empty SSID network info dictionary.
  *  @see CNCopyCurrentNetworkInfo */
- (NSDictionary *)fetchSSIDInfo
{
    NSArray *interfaceNames = CFBridgingRelease(CNCopySupportedInterfaces());
   // NSLog(@"%s: Supported interfaces: %@", __func__, interfaceNames);
    
    NSDictionary *SSIDInfo;
    for (NSString *interfaceName in interfaceNames) {
        SSIDInfo = CFBridgingRelease(
                                     CNCopyCurrentNetworkInfo((__bridge CFStringRef)interfaceName));
      //  NSLog(@"%s: %@ => %@", __func__, interfaceName, SSIDInfo);
        
        BOOL isNotEmpty = (SSIDInfo.count > 0);
        if (isNotEmpty) {
            break;
        }
    }
    return SSIDInfo;
}

- (NSString *) getNetMask
{
    NSString *netmask = @"error";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = 0;
    
    // retrieve the current interfaces - returns 0 on success
    success = getifaddrs(&interfaces);
    
    if (success == 0)
    {
        temp_addr = interfaces;
        
        while(temp_addr != NULL)
        {
            // check if interface is en0 which is the wifi connection on the iPhone
            if(temp_addr->ifa_addr->sa_family == AF_INET)
            {
                if([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"])
                {
                    netmask = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_netmask)->sin_addr)];
                }
            }
            
            temp_addr = temp_addr->ifa_next;
        }
    }
    
    freeifaddrs(interfaces);
    
    return netmask;
}

//convert NSstring to unsigned long where NSString is an ipV4 192.168.1.24
- (unsigned long)StrIp2UnsignedLong:(NSString *)ip {
    unsigned long ans = 0;
    
    //split string into components (first octet, second octet, etc)
    NSArray *tmp = [ip componentsSeparatedByString:@"."];
    NSMutableArray *octets = [[NSMutableArray alloc]init];
    
    for (int i = 0; i < [tmp count]; i++) {
        NSNumberFormatter * f = [[NSNumberFormatter alloc] init];
        [f setNumberStyle:NSNumberFormatterDecimalStyle];
        NSNumber * mynumber = [f numberFromString:tmp[i]];
        octets[i] = mynumber;
    }
    
    ans = [octets[0] unsignedIntValue] * 16777216 + [octets[1] unsignedIntValue] * 65536 + [octets[2] unsignedIntValue] * 256 + [octets[3] unsignedIntValue];
    
    return ans;
    
}

//Convert NSString ipV4 to unsigned int
- (unsigned int)StrIp2UnsignedInt:(NSString *)ip {
    unsigned int ans = 0;
    
    //split string into components (first octet, second octet, etc)
    NSArray *tmp = [ip componentsSeparatedByString:@"."];
    NSMutableArray *octets = [[NSMutableArray alloc]init];
    
    for (int i = 0; i < [tmp count]; i++) {
        NSNumberFormatter * f = [[NSNumberFormatter alloc] init];
        [f setNumberStyle:NSNumberFormatterDecimalStyle];
        NSNumber * mynumber = [f numberFromString:tmp[i]];
        octets[i] = mynumber;
    }
    
    ans = [octets[0] unsignedIntValue] * 16777216 + [octets[1] unsignedIntValue] * 65536 + [octets[2] unsignedIntValue] * 256 + [octets[3] unsignedIntValue];
    
    return ans;
    
}

//unsigned Int convert back to NSString IPv4
- (NSString *)unsignedInt2StrIp:(in_addr_t)ip
{
    unsigned int part1, part2, part3, part4;
    
    part1 = ip/16777216;
    ip = ip%16777216;
    part2 = ip/65536;
    ip = ip%65536;
    part3 = ip/256;
    ip = ip%256;
    part4 = ip;
    
    NSString *fullIP = [NSString stringWithFormat:@"%d.%d.%d.%d", part1, part2, part3, part4];
    
    return fullIP;
}

//reverse NSString
- (NSString *)reverseString:(NSString *)str {
    NSMutableString * reverseString = [NSMutableString string];
    NSInteger charIndex = [str length];
    
    while (charIndex > 0) {
        charIndex--;
        NSRange subStrRange = NSMakeRange(charIndex, 1);
        [reverseString appendString:[str substringWithRange:subStrRange]];
    }
    
    return reverseString;
}

@end
