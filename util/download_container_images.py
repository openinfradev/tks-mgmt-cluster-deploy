#!/usr/bin/env python3
import os
import subprocess
import sys
import tempfile
import yaml

def pull_docker_image(image):
  # pull_image = subprocess.Popen(['docker','pull',image], stdout=subprocess.PIPE)
  # (out,err) = pull_image.communicate()
  # print(out)
  print(image)

def download_container_images(manifest):
  
  print("##### Download container images")
  image_list=[]
  with open(manifest) as f:
    releases = list(yaml.load_all(f, Loader=yaml.FullLoader))
    for release in releases:

      release['spec']['values']
      name = release['spec']['chart']['name']
      version = release['spec']['chart']['version']
      repository = release['spec']['chart']['repository']
      print("Chart Name: {}".format(name)) 
      tmp = tempfile.NamedTemporaryFile(delete=False)
      try:
        tmp.write(yaml.dump(release['spec']['values']).encode())
        tmp.flush()
        print("helm template --repo {} --version {} -f {} {}".format(repository,version,tmp.name,name))
        rawhelmtemplate = subprocess.Popen(['helm', 'template', \
                  '--repo', repository, \
                '--version', version, \
                '-f', tmp.name, \
                name], \
                stdout=subprocess.PIPE)
        (out,err) = rawhelmtemplate.communicate()
        helmyamls = yaml.load_all(out, Loader=yaml.SafeLoader)
        for helmyaml in helmyamls:
          if helmyaml is not None and 'spec' in helmyaml:
            print(helmyaml)
            spec = helmyaml['spec']
            if 'template' in spec:
              template = spec['template']
              if 'spec' in template:
                spec = template['spec']
                if 'containers' in spec:
                  for container in spec['containers']:
                    print("Case 1 - container: {}".format(container['image']))
                    pull_docker_image(container['image'])
                    image_list.append(container['image'])
                if 'initContainers' in spec:
                  for initcontainer in spec['initContainers']:
                    print("Case 2 - Init container: {}".format(initcontainer['image']))
                    pull_docker_image(initcontainer['image'])
                    image_list.append(initcontainer['image'])
            if 'containers' in spec:
              for container in spec['containers']:
                print("Case 3 - spec container: {}".format(container['image']))
                pull_docker_image(container['image'])
                image_list.append(container['image'])
            if 'image' in spec:
              print("Case 4 - spec image: {}".format(spec['image']))
              pull_docker_image(spec['image'])
              image_list.append(spec['image'])
      finally:
        os.unlink(tmp.name)
        tmp.close()
      
    return set(image_list)
def main():
  if len(sys.argv) != 3:
    print("Error: This file needs manifest argument.")
    print("Usage: download_container_images.py <MANIFEST YAML> <output>")
    exit(1)
  manifest = sys.argv[1]
  outdir = sys.argv[2]

  f = open(outdir+'/'+manifest.split('/')[-1]+'.docker-images', 'w')
  for image in download_container_images(manifest):
    f.write(image+'\n')
  f.close()

if __name__ == "__main__":
    main()