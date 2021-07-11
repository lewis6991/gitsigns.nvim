#!/usr/bin/env python3
import os
import subprocess
from jinja2 import Environment, FileSystemLoader

def generate_file(name, outpath, **kwargs):
    env = Environment(loader=FileSystemLoader(os.path.dirname(__file__)+'/../templates'))
    template = env.get_template(name)
    path = os.path.join(outpath, name)
    with open(path, 'w') as fp:
        fp.write(template.render(kwargs))

if __name__ == '__main__':
    generate_file('async.d.tl', '../types/plenary/')
