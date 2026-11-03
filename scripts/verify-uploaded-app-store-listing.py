#!/usr/bin/env python3
"""Read-only independent verification of the five-panel Apple upload readback."""
import argparse
import copy
import datetime
import hashlib
import json
import re
import struct
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CAMPAIGN = ROOT / 'artifacts/app-store-listing/2026-11-03'
BUCKETS = {
    'APP_IPHONE_61': 'iphone-dynamic-island-medium',
    'APP_IPHONE_67': 'iphone-dynamic-island-large',
    'APP_IPHONE_65': 'iphone-face-id-large',
    'APP_IPAD_PRO_3GEN_129': 'ipad-13',
    'APP_IPAD_PRO_3GEN_11': 'ipad-11',
}
LOCALES = {'en-US', 'en-GB', 'en-AU', 'es-ES', 'es-MX'}

def demand(value, message):
    if not value:
        raise ValueError(message)

def read_report(path):
    raw = Path(path).read_text()
    try:
        result = json.loads(raw)
        if isinstance(result, dict) and 'listing' in result:
            return result
    except json.JSONDecodeError:
        pass
    cleaned = []
    for line in raw.splitlines():
        line = re.sub(r'\x1b\[[0-9;]*m', '', line)
        if line.count('\t') >= 2:
            line = line.split('\t', 2)[2]
        line = re.sub(r'^\ufeff?\d{4}-\d{2}-\d{2}T\S+\s+', '', line)
        cleaned.append(line)
    cleaned = '\n'.join(cleaned)
    marker = cleaned.find('"app_id":')
    demand(marker >= 0, 'No App Store status report found in log')
    start = cleaned.rfind('{', 0, marker)
    return json.JSONDecoder().raw_decode(cleaned[start:])[0]

def verify(report, version='1.0.9', status_run=None):
    demand(str(report['app_id']) == '6762563132', 'Unexpected App Store app id')
    manifest_path = CAMPAIGN / 'manifest.json'
    manifest = json.loads(manifest_path.read_text())
    families = {f['id']: f for f in manifest['families']}
    listing = report['listing']
    demand(listing and listing['version'] == version, f'Expected target listing {version}')
    version_record = next(v for v in report['versions'] if v['id'] == listing['version_id'])
    demand(version_record['attributes']['versionString'] == version, 'Version id/number mismatch')
    localizations = listing['localizations']
    demand(len(localizations) == 5 and {l['locale'] for l in localizations} == LOCALES,
           'Expected exactly five selected listing locales')
    results = []
    total = 0
    for locale in sorted(localizations, key=lambda x: x['locale']):
        nonempty = [s for s in locale['screenshot_sets'] if s['screenshots']]
        demand(len(nonempty) == 5 and {s['display_type'] for s in nonempty} == set(BUCKETS),
               f"{locale['locale']}: unexpected/missing nonempty screenshot buckets")
        sets = []
        for bucket in sorted(nonempty, key=lambda x: x['display_type']):
            family_id = BUCKETS[bucket['display_type']]
            family = families[family_id]
            images = bucket['screenshots']
            demand(len(images) == 5, f"{locale['locale']}/{family_id}: expected exactly five assets, got {len(images)}")
            expected_names = [f"{family_id}-{Path(p).name}" for p in family['files']]
            demand([img['filename'] for img in images] == expected_names,
                   f"{locale['locale']}/{family_id}: filename/order mismatch")
            records = []
            for index, (img, relative) in enumerate(zip(images, family['files']), 1):
                source = CAMPAIGN / relative
                demand(str(source.resolve()).startswith(str(CAMPAIGN.resolve()) + '/'), 'Source escapes campaign')
                data = source.read_bytes()
                demand(data[:8] == b'\x89PNG\r\n\x1a\n', f'Invalid local source PNG {relative}')
                dimensions = list(struct.unpack('>II', data[16:24]))
                demand(dimensions == [family['width'], family['height']], f'Unexpected local dimensions {relative}')
                demand(img['size'] == len(data), f"{locale['locale']}/{family_id}/{index}: uploaded fileSize mismatch")
                demand([img['width'], img['height']] == dimensions,
                       f"{locale['locale']}/{family_id}/{index}: Apple image dimensions mismatch")
                delivery = img['delivery']
                demand(delivery['state'] == 'COMPLETE' and not delivery.get('errors'),
                       f"{locale['locale']}/{family_id}/{index}: asset not COMPLETE without errors")
                records.append({'position': index, 'id': img['id'], 'filename': img['filename'],
                                'sourceFileBytes': len(data), 'dimensions': dimensions,
                                'sourceSHA256': hashlib.sha256(data).hexdigest(), 'delivery': 'COMPLETE'})
            total += len(images)
            sets.append({'displayType': bucket['display_type'], 'family': family_id, 'count': 5,
                         'ordered01Through05': True, 'reportedFileSizesMatchSources': True,
                         'dimensionsMatchSources': True, 'allDeliveryComplete': True, 'assets': records})
        results.append({'locale': locale['locale'], 'count': 25, 'sets': sets})
    demand(total == 125, 'Expected exactly 125 uploaded assets')
    return {'verifiedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'statusRun': status_run, 'appId': report['app_id'], 'versionId': listing['version_id'],
            'version': version, 'versionState': version_record['attributes']['appStoreState'],
            'manifestSHA256': hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
            'sourceCampaign': 'artifacts/app-store-listing/2026-11-03', 'assetCount': total,
            'localeCount': 5, 'bucketsPerLocale': 5, 'assetsPerBucket': 5, 'checksPassed': True,
            'note': 'Compared Apple upload metadata fileSize and image dimensions to each local PNG; source SHA-256 values identify local files, not CDN recompression hashes.',
            'appleWrites': False, 'locales': results}

def make_offline_fixture():
    """Build a synthetic Apple-shaped response; this is never upload evidence."""
    manifest = json.loads((CAMPAIGN / 'manifest.json').read_text())
    families = {family['id']: family for family in manifest['families']}
    localizations = []
    for locale in sorted(LOCALES):
        sets = []
        for display, family_id in BUCKETS.items():
            family = families[family_id]
            images = []
            for index, relative in enumerate(family['files'], 1):
                data = (CAMPAIGN / relative).read_bytes()
                images.append({
                    'id': f'offline-{locale}-{family_id}-{index}',
                    'filename': family_id + '-' + Path(relative).name,
                    'size': len(data),
                    'width': family['width'],
                    'height': family['height'],
                    'delivery': {'state': 'COMPLETE', 'errors': []},
                })
            sets.append({'display_type': display, 'screenshots': images})
        localizations.append({'locale': locale, 'screenshot_sets': sets})
    return {
        'app_id': '6762563132',
        'listing': {
            'version': '1.0.9', 'version_id': 'offline-fixture',
            'localizations': localizations,
        },
        'versions': [{
            'id': 'offline-fixture',
            'attributes': {'versionString': '1.0.9',
                           'appStoreState': 'PREPARE_FOR_SUBMISSION'},
        }],
    }


def self_test():
    """Exercise nine controls without network access or writing a proof."""
    original = make_offline_fixture()
    demand(verify(original)['assetCount'] == 125,
           'Offline complete fixture must pass')
    controls = ['complete 125-asset fixture']
    mutations = [
        ('missing locale',
         lambda report: report['listing']['localizations'].pop()),
        ('missing panel',
         lambda report: report['listing']['localizations'][0]
         ['screenshot_sets'][0]['screenshots'].pop()),
        ('incorrect order',
         lambda report: report['listing']['localizations'][0]
         ['screenshot_sets'][0]['screenshots'].reverse()),
        ('incorrect uploaded file size',
         lambda report: report['listing']['localizations'][0]
         ['screenshot_sets'][0]['screenshots'][0].update(size=1)),
        ('incorrect image dimensions',
         lambda report: report['listing']['localizations'][0]
         ['screenshot_sets'][0]['screenshots'][0].update(width=1)),
        ('pending asset processing',
         lambda report: report['listing']['localizations'][0]
         ['screenshot_sets'][0]['screenshots'][0]['delivery']
         .update(state='PROCESSING')),
        ('wrong App Store app',
         lambda report: report.update(app_id='wrong-app')),
    ]
    for label, mutate in mutations:
        report = copy.deepcopy(original)
        mutate(report)
        try:
            verify(report)
        except ValueError:
            controls.append(label)
        else:
            raise ValueError(f'Invalid offline fixture passed: {label}')
    with tempfile.TemporaryDirectory(prefix='proestimate-readback-control-') as folder:
        log = Path(folder) / 'offline-github.log'
        log.write_text('\n'.join(
            'Job\tStep\t2026-11-03T00:00:00Z ' + line
            for line in json.dumps(original, indent=2).splitlines()
        ))
        demand(read_report(log) == original, 'GitHub log parser control failed')
        controls.append('GitHub timestamped log parser')
    demand(len(controls) == 9, 'Expected exactly nine offline controls')
    print(json.dumps({'selfTest': True, 'controlsPassed': len(controls),
                      'controls': controls, 'appleAccess': False,
                      'realUploadProof': False}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', nargs='?', help='asc_status JSON or GitHub log')
    parser.add_argument('--version', default='1.0.9', help='Exact expected listing version')
    parser.add_argument('--status-run', type=int, help='GitHub readback run id for provenance')
    parser.add_argument('--out', help='Optional local proof JSON destination')
    parser.add_argument('--self-test', action='store_true',
                        help='Run nine offline controls; no Apple access or proof written')
    args = parser.parse_args()
    if args.self_test:
        if args.report or args.out:
            parser.error('--self-test cannot be combined with report or --out')
        self_test()
        return
    if not args.report:
        parser.error('provide an asc_status report or --self-test')
    proof = verify(read_report(args.report), args.version, args.status_run)
    if args.out:
        Path(args.out).write_text(json.dumps(proof, indent=2) + '\n')
    print(json.dumps({key: proof[key] for key in [
        'version', 'versionState', 'assetCount', 'localeCount',
        'bucketsPerLocale', 'assetsPerBucket', 'checksPassed', 'appleWrites',
    ]}))


if __name__ == '__main__':
    main()
