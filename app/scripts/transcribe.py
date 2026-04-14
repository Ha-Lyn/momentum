import sys
from openai import OpenAI

def transcribe_audio(audio_path: str) -> str:
    """
    Transcribes the given audio file using OpenAI's Whisper model.
    Returns the transcription text.
    """
    client = OpenAI()
    with open(audio_path, "rb") as audio_file:
        transcription = client.audio.transcriptions.create(
            model="whisper-1", 
            file=audio_file,
            language="en"
        )
    return transcription.text

def main():
    if len(sys.argv) < 2:
        print("Error: Audio file path is required.", file=sys.stderr)
        sys.exit(1)

    audio_path = sys.argv[1]
    
    try:
        # Get the returning transcription text
        transcription_text = transcribe_audio(audio_path)
        # Print in the terminal
        print(transcription_text)
    except Exception as e:
        print(f"Error during transcription: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()