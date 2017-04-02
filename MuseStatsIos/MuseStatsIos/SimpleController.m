//
//  SimpleController.m
//  MuseStatsIos
//
//  Created by Yue Huang on 2015-09-01.
//  Copyright (c) 2015 InteraXon. All rights reserved.
//

#import "SimpleController.h"
#import <CoreBluetooth/CoreBluetooth.h>

@interface SimpleController () <CBCentralManagerDelegate>
@property IXNMuseManagerIos * manager;
@property (weak, nonatomic) IXNMuse * muse;
@property (nonatomic) NSMutableArray* logLines;
@property (nonatomic) BOOL lastBlink;
@property (nonatomic) BOOL lastJawClench;
@property (nonatomic, strong) CBCentralManager * btManager;
@property (atomic) BOOL btState;
@end

@implementation SimpleController

- (void)viewDidLoad {
    [super viewDidLoad];
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    if (!self.manager) {
        self.manager = [IXNMuseManagerIos sharedManager];
    }
}

- (instancetype) initWithNibName:(NSString *)nibNameOrNil
                          bundle:(NSBundle *)nibBundleOrNil {
    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
        self.manager = [IXNMuseManagerIos sharedManager];
        [self.manager setMuseListener:self];
        self.tableView = [[UITableView alloc] init];

        self.logView = [[UITextView alloc] init];
        self.logLines = [NSMutableArray array];
        [self.logView setText:@""];
        
        [[IXNLogManager instance] setLogListener:self];
        NSDateFormatter *dateFormatter=[[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"yyyy-MM-dd hh:mm:ss"];
        NSString * dateStr = [[dateFormatter stringFromDate:[NSDate date]] stringByAppendingString:@".log"];
        NSLog(@"%@", dateStr);
        
        self.btManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil options:nil];
        self.btState = FALSE;
    }
    return self;
}

- (void)log:(NSString *)fmt, ... {
    va_list args;
    va_start(args, fmt);
    NSString *line = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSLog(@"%@", line);
    [self.logLines insertObject:line atIndex:0];
    
    dispatch_async(dispatch_get_main_queue(), ^ {
        [self.logView setText:[self.logLines componentsJoinedByString:@"\n"]];
    });
}

- (void)receiveLog:(nonnull IXNLogPacket *)l {
  [self log:@"%@: %llu raw:%d %@", l.tag, l.timestamp, l.raw, l.message];
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    self.btState = (self.btManager.state == CBCentralManagerStatePoweredOn);
}

- (bool)isBluetoothEnabled {
    return self.btState;
}

- (void)museListChanged {
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView
 numberOfRowsInSection:(NSInteger)section {
    return [[self.manager getMuses] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *simpleTableIdentifier = @"nil";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:
                             simpleTableIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:simpleTableIdentifier];
    }
    NSArray * muses = [self.manager getMuses];
    if (indexPath.row < [muses count]) {
        IXNMuse * muse = [[self.manager getMuses] objectAtIndex:indexPath.row];
        cell.textLabel.text = [muse getName];
        if (![muse isLowEnergy]) {
            cell.textLabel.text = [cell.textLabel.text stringByAppendingString:
                                   [muse getMacAddress]];
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView
didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray * muses = [self.manager getMuses];
    if (indexPath.row < [muses count]) {
        IXNMuse * muse = [muses objectAtIndex:indexPath.row];
        @synchronized (self.muse) {
            if(self.muse == nil) {
                self.muse = muse;
            }else if(self.muse != muse) {
                [self.muse disconnect];
                self.muse = muse;
            }
        }
        [self connect];
        [self log:@"======Choose to connect muse %@ %@======\n",
              [self.muse getName], [self.muse getMacAddress]];
    }
}

- (void)receiveMuseConnectionPacket:(IXNMuseConnectionPacket *)packet
                               muse:(IXNMuse *)muse {
    NSString *state;
    switch (packet.currentConnectionState) {
        case IXNConnectionStateDisconnected:
            state = @"disconnected";
            break;
        case IXNConnectionStateConnected:
            state = @"connected";
            break;
        case IXNConnectionStateConnecting:
            state = @"connecting";
            break;
        case IXNConnectionStateNeedsUpdate: state = @"needs update"; break;
        case IXNConnectionStateUnknown: state = @"unknown"; break;
        default: NSAssert(NO, @"impossible connection state received");
    }
    [self log:@"connect: %@", state];
}

- (void) connect {
    [self.muse registerConnectionListener:self];
    [self.muse registerDataListener:self
                               type:IXNMuseDataPacketTypeArtifacts];
    [self.muse registerDataListener:self
                               type:IXNMuseDataPacketTypeAlphaAbsolute];
    /*
    [self.muse registerDataListener:self
                               type:IXNMuseDataPacketTypeEeg];
     */
    [self.muse runAsynchronously];
}

- (void)receiveMuseDataPacket:(IXNMuseDataPacket *)packet
                         muse:(IXNMuse *)muse {
    /*if (packet.packetType == IXNMuseDataPacketTypeAlphaAbsolute ||
            packet.packetType == IXNMuseDataPacketTypeEeg) {
        [self log:@"%5.2f %5.2f %5.2f %5.2f",
         [packet.values[IXNEegEEG1] doubleValue],
         [packet.values[IXNEegEEG2] doubleValue],
         [packet.values[IXNEegEEG3] doubleValue],
         [packet.values[IXNEegEEG4] doubleValue]];
    }*/
    /*
    if (packet.packetType == IXNMuseDataPacketTypeAlphaAbsolute ||
        packet.packetType == IXNMuseDataPacketTypeGyro) {
        [self log:@"%5.2f %5.2f %5.2f",
         [packet.values[IXNGyroX] doubleValue],
         [packet.values[IXNGyroY] doubleValue],
         [packet.values[IXNGyroZ] doubleValue]];
    }*/
    /*
    if (packet.packetType == IXNMuseDataPacketTypeAlphaAbsolute ||
        packet.packetType == IXNMuseDataPacketTypeAccelerometer) {
        [self log:@"%5.2f %5.2f",
         [packet.values[IXNAccelerometerX] doubleValue],
         [packet.values[IXNAccelerometerY] doubleValue]];
    }*/
    /*
    if (packet.packetType == IXNMuseDataPacketTypeAlphaAbsolute ||
        packet.packetType == IXNMuseDataPacketTypeIsGood) {
        [self log:@"%5.2f %5.2f %5.2f %5.2f",
         [packet.values[0] doubleValue],
         [packet.values[1] doubleValue],
         [packet.values[2] doubleValue],
         [packet.values[3] doubleValue]];
    }
     */
    if (packet.packetType == IXNMuseDataPacketTypeAlphaAbsolute) {
        [self log:@"%5.2f %5.2f %5.2f %5.2f",
         [packet.values[IXNEegEEG1] doubleValue],
         [packet.values[IXNEegEEG2] doubleValue],
         [packet.values[IXNEegEEG3] doubleValue],
         [packet.values[IXNEegEEG4] doubleValue]];
    }
    
    
}

- (void)receiveMuseArtifactPacket:(IXNMuseArtifactPacket *)packet
                             muse:(IXNMuse *)muse {
    if (packet.blink && packet.blink != self.lastBlink) {
        [self log:@"blink detected"];
        
    }
    self.lastBlink = packet.blink;
    
    if (packet.jawClench && packet.jawClench != self.lastJawClench) {
        [self log:@"jaw clench detected"];
    }
    self.lastJawClench = packet.jawClench;
}

- (void)applicationWillResignActive {
    NSLog(@"disconnecting before going into background");
    [self.muse disconnect];
}

- (IBAction)disconnect:(id)sender {
    if (self.muse) [self.muse disconnect];
}

- (IBAction)scan:(id)sender {
    [self.manager startListening];
    [self.tableView reloadData];
}

- (IBAction)stopScan:(id)sender {
    [self.manager stopListening];
    [self.tableView reloadData];
}
@end
