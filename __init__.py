"""
Web interface for Dothraki translator
"""

import os
import sys
import socket
from flask import Flask, render_template, redirect, url_for, request
import subprocess

# ======================================================================================================================
# Globals
# ======================================================================================================================
app = Flask(__name__)
script_dir = os.path.dirname(os.path.abspath(__file__))

# ======================================================================================================================
# Start translation units
# ======================================================================================================================
subprocess.Popen(["perl", "{}/Doth2Eng/SyntacticTransfer_SS.pl".format(script_dir)])
subprocess.Popen(["perl", "{}/Eng2Doth/SyntacticTransfer_SS.pl".format(script_dir)])


# ======================================================================================================================
# Routes
# ======================================================================================================================
@app.route("/")
def home():
    return redirect(url_for('index'))


@app.route("/main")
def index():
    return render_template("index.html")

@app.route("/about")
def about():
    return render_template("about.html")


@app.route('/Doth2Eng', methods=['GET','POST'])
def Doth2Eng():
    if request.method == 'GET':
        return render_template('Doth2Eng.html')
    elif request.method == 'POST':
        return render_template('Doth2Eng.html')


@app.route('/Eng2Doth', methods=['GET','POST'])
def Eng2Doth():
    if request.method == 'GET':
        return render_template('Eng2Doth.html')
    elif request.method == 'POST':
        return render_template('Eng2Doth.html')


@app.route('/translate_FromDothraki', methods=['GET','POST'])
def translate_DE():
    if request.method == 'POST':
        _dothraki = request.form['inputDothraki']
        translation = translate_DE(_dothraki)
        return render_template('translate_FromDothraki.html', dothraki=_dothraki, translation=translation)

@app.route('/translate_FromEnglish', methods=['GET','POST'])
def translate_ED():
    if request.method == 'POST':
        _english = request.form['inputEnglish']
        translation = translate_ED(_english)
        return render_template('translate_FromEnglish.html', english=_english, translation=translation)

# ======================================================================================================================
# Functions
# ======================================================================================================================

def translate_DE(input):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_address = ('localhost', 7000)
    sock.connect(server_address)
    sock.send("{}\n".format(input))
    translation = sock.recv(1024)
    return translation

def translate_ED(input):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_address = ('localhost', 9000)
    sock.connect(server_address)
    sock.send("{}\n".format(input))
    translation = sock.recv(1024)
    return translation

def override_url_for():
    return dict(url_for=dated_url_for)


def dated_url_for(endpoint, **values):
    if endpoint == 'static':
        filename = values.get('filename', None)
        if filename:
            file_path = os.path.join(app.root_path,
                                     endpoint, filename)
            values['q'] = int(os.stat(file_path).st_mtime)
    return url_for(endpoint, **values)


# ======================================================================================================================
# Run
# ======================================================================================================================
if __name__ == "__main__":
    app.run()
