"""Compile and execute the AIR dispatcher against local fixture objects only."""
import argparse
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sdk', type=Path, required=True)
args = parser.parse_args()
sdk = args.sdk.resolve()
root = Path(__file__).resolve().parents[2]
out = root / 'output/bridge-check'
out.mkdir(parents=True, exist_ok=True)
subprocess.run(['java', '-Dflexlib=' + str(sdk / 'frameworks'), '-jar', str(sdk / 'lib/mxmlc-cli.jar'),
                '+configname=air', '-source-path=' + str(root / 'native'), '-debug=true',
                '-output=' + str(out / 'BridgeFixture.swf'),
                str(root / 'experimental/SkuaMobile/AirChecks/BridgeFixture.as')], check=True, timeout=90)
descriptor = out / 'BridgeFixture-app.xml'
descriptor.write_text('''<application xmlns="http://ns.adobe.com/air/application/51.1">
<id>com.personal.aqw.bridgefixture</id><versionNumber>1.0.0</versionNumber>
<filename>BridgeFixture</filename><initialWindow><content>BridgeFixture.swf</content>
<visible>false</visible></initialWindow></application>''')
result = subprocess.run([str(sdk / 'bin/adl'), '-profile', 'desktop', str(descriptor), str(out)],
                        capture_output=True, text=True, timeout=30)
text = result.stdout + result.stderr
(out / 'dispatcher.log').write_text(text)
print(text, flush=True)
if result.returncode or 'PASS AIR bridge: 12 dispatcher checks;' not in text or 'FAIL AIR bridge:' in text:
    raise RuntimeError('AIR dispatcher fixture failed; see output/bridge-check/dispatcher.log')
