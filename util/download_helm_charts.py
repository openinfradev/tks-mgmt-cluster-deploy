#!/usr/bin/env python3

import subprocess
import sys
import yaml
from os import walk
from pathlib import Path


def main():
    print("Usage: python download_helm_charts.py [<MANIFEST YAML>] [<download dir>]")
    manifest = 'hr-manifests'
    download_dir = 'charts/'
    if len(sys.argv) == 2:
        manifest = sys.argv[1]
    elif len(sys.argv) == 3:
        manifest = sys.argv[1]
        download_dir = sys.argv[2]+'/'
    Path(download_dir).mkdir(parents=True, exist_ok=True)

    print("###### Download helm charts")
    files = []
    for (_, _, filenames) in walk(manifest):
        files.extend(filenames)
        break

    print(f"files = ({files})")
    for file in files:
        with open(manifest + '/' + file) as f:
            releases = list(yaml.load_all(f, Loader=yaml.FullLoader))
            for release in releases:
                name = release['spec']['chart']['name']
                version = release['spec']['chart']['version']
                repository = release['spec']['chart']['repository']
                print('helm pull --repo {} --version {} -d {} {}'.format(repository, version, download_dir, name))

                process = subprocess.Popen(['helm', 'pull',
                                            '--repo', repository,
                                            '--version', version,
                                            '-d', download_dir,
                                            name])
                process.wait()
                # chart_filename = download_dir+name+'-'+version+'.tgz'
                # untar = subprocess.Popen(['tar', 'xzf', chart_filename,
                #                           '-C', download_dir,
                #                           '--warning=no-timestamp'])
                # untar.wait()
                # os.remove(chart_filename)


if __name__ == '__main__':
    main()
