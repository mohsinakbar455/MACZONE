// Inherited MacsyZones private window/Space interfaces. GPL-3.0.
#import <AppKit/AppKit.h>
AXError _AXUIElementGetWindow(AXUIElementRef element, uint32_t *identifier);
extern CFArrayRef CGSCopyManagedDisplaySpaces(int cid);
extern int CGSMainConnectionID(void);
extern uint64_t CGSGetActiveSpace(int cid);
