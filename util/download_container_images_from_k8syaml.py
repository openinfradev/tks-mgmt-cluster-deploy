#!/usr/bin/env python3
import os
import subprocess
import sys
import tempfile
import yaml

def pull_podman_image(image):
    print("===>>> Pulling image: " + image)
    pull_image = subprocess.Popen(['podman','pull',image], \
                                  stdout=subprocess.PIPE)
    (out,err) = pull_image.communicate()
    print(out)

def download_container_images_from_yaml(yamlFile):

    print("##### Download container images")
    with open(yamlFile) as f:
        k8syamls = yaml.load_all(f, Loader=yaml.SafeLoader)
        for k8syaml in k8syamls:
            if k8syaml is not None and 'spec' in k8syaml:
                #print(k8syaml)
                spec = k8syaml['spec']
                if 'template' in spec:
                    template = spec['template']
                    if 'spec' in template:
                        spec = template['spec']
                        if 'containers' in spec:
                            for container in spec['containers']:
                                print("Case 1 - container: {}".format(container['image']))
                                pull_podman_image(container['image'])
                        if 'initContainers' in spec:
                            for initcontainer in spec['initContainers']:
                                print("Case 2 - Init container: {}".format(initcontainer['image']))
                                pull_podman_image(initcontainer['image'])
                if 'containers' in spec:
                    for container in spec['containers']:
                        print("Case 3 - spec container: {}".format(container['image']))
                        pull_podman_image(container['image'])
                if 'image' in spec:
                    print("Case 4 - spec image: {}".format(spec['image']))
                    pull_podman_image(spec['image'])

def main():
    if len(sys.argv) != 2:
        print("Error: This file needs a yaml file argument.")
        print("Usage: download_container_images_from_yaml.py <YAML>")
        exit(1)
    yamlFile = sys.argv[1]
    download_container_images_from_yaml(yamlFile)

if __name__ == "__main__":
        main()
