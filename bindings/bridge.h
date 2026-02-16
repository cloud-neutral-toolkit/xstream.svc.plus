#ifndef BRIDGE_H
#define BRIDGE_H

#include <stdint.h>

char* WriteConfigFiles(const char* xrayPath,
                       const char* xrayContent,
                       const char* servicePath,
                       const char* serviceContent,
                       const char* vpnPath,
                       const char* vpnContent,
                       const char* password);

char* StartNodeService(const char* name);
char* StopNodeService(const char* name);
int32_t CheckNodeStatus(const char* name);
char* CreateWindowsService(const char* name,
                           const char* execPath,
                           const char* configPath);
char* PerformAction(const char* action, const char* password);
int32_t IsXrayDownloading(void);
char* StartXray(const char* config);
char* StopXray(void);
long long StartXrayTunnel(const char* config);
long long StartXrayTunnelWithFd(const char* config, int32_t tunFd);
int32_t SubmitInboundPacket(long long handle,
                            const uint8_t* data,
                            int32_t length,
                            int32_t protocol);
char* StopXrayTunnel(long long handle);
char* FreeXrayTunnel(long long handle);
void FreeCString(char* str);

#endif // BRIDGE_H
