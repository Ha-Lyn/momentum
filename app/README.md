This is the prototype of Momentum. An app which is purpose is to help me registry entries in such a diary form via audio which will be transcribed into a markdown file.

Currently the project is structured as a Electron app (Typescript) with side scripts written in Python and Bash/Zsh.

The sh and python scripts are generated from a spawn process in Node js environment. Which is honestly coming in handy and expanding ideias I never though that were possible.

The capture of audio is done via a widely used software; ffmpeg. When you start the project a script will be runned to download a compact version of the software if its not found in your pc. Currently only Mac Os is supported

Since Mac-Os is the only OS supported, one question naturally arrises which is why don't create the app in Swift? And the current answer is not yet, but is a great ideia.

I'm currently trying to implement some source of control of recorded and transcription files whitout recurring to web apps (i.e. cloud backend) since is destined to be a independant app that runs entirely in your local machine.

I acctually have an ideia for that and goes around with using SqLite which will have some sort of control and is very lightweighted.


### Update 25/04/2026
We have a beta build ready to be tested. The application can now record audio and transcribe it to a markdown file. The app still runs soly on MacOs systems. Besides missing an UI it's fully functional for the main concept.

For now its build based on Electron-Js (for it's simplicity) and runs a python script using the "uv" ecosystem. 
The transcriptions currently runs using the OpenAI Whisper model. For usage a OPEN_API_KEY must be set in the enviroment (i.e. export OPEN_API_KEY='...').

I did not had a lot of time investment in the last couple weeks since work cought up to me quickly. I hope it settles down in the next month. PLEASE AI SUGGESTION STOP MAKING DUMB SUGGESTIONS. 