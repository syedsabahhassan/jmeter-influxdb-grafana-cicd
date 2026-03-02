# JMeter Plugins

This project uses the following JMeter plugins. The CI pipeline downloads them automatically via the Plugin Manager CLI.

## Required Plugins

| Plugin ID | Name | Purpose |
|-----------|------|---------|
| `jpgc-casutg` | Custom Thread Groups | Ultimate Thread Group for step-load patterns |
| `jpgc-functions` | Custom JMeter Functions | Additional functions like `__groovy` |
| `jpgc-json` | JSON Plugins | Enhanced JSON Path Extractor |
| `jpgc-synthesis` | Synthesis Report | Detailed summary reports |
| `jpgc-graphs-additional` | Additional Graphs | Extended charting in GUI mode |

## Installation (Local Development)

### Option A: Plugin Manager GUI
1. Download [JMeter Plugin Manager](https://jmeter-plugins.org/wiki/PluginsManager/)
2. Place `jmeter-plugins-manager-*.jar` in `$JMETER_HOME/lib/ext/`
3. Restart JMeter
4. Navigate to Options > Plugins Manager
5. Search and install each plugin listed above

### Option B: Command Line (CI/CD)
```bash
# Download Plugin Manager CLI
wget -q https://search.maven.org/remotecontent?filepath=kg/apc/cmdrunner/2.3/cmdrunner-2.3.jar -O cmdrunner.jar
wget -q https://search.maven.org/remotecontent?filepath=kg/apc/jmeter-plugins-manager/1.9/jmeter-plugins-manager-1.9.jar -O $JMETER_HOME/lib/ext/jmeter-plugins-manager-1.9.jar

# Install plugins
java -jar cmdrunner.jar --tool org.jmeterplugins.repository.PluginManagerCMD install jpgc-casutg,jpgc-functions,jpgc-json,jpgc-synthesis
```

## JMeter Version
Tested with **Apache JMeter 5.6.3**

## InfluxDB Backend Listener
The `InfluxdbBackendListenerClient` is **built into JMeter 3.3+** — no plugin required.
Configure it with:
- `influxdbUrl`: `http://<influxdb-host>:8086/write?db=jmeter`
- `measurement`: `jmeter`
- `percentiles`: `90;95;99`
