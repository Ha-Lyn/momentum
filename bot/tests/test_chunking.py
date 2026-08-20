from textutil import split_long_text


def test_short_text_single_chunk():
    assert split_long_text("olá") == ["olá"]


def test_exact_limit_single_chunk():
    text = "a" * 100
    assert split_long_text(text, limit=100) == [text]


def test_long_text_no_newlines_splits_at_limit():
    text = "a" * 250
    assert split_long_text(text, limit=100) == ["a" * 100, "a" * 100, "a" * 50]


def test_splits_prefer_newline_boundaries():
    text = ("a" * 90) + "\n" + ("b" * 90) + "\n" + ("c" * 90)
    assert split_long_text(text, limit=100) == ["a" * 90, "b" * 90, "c" * 90]


def test_all_chunks_within_limit():
    text = "line one\n" * 200
    chunks = split_long_text(text, limit=500)
    assert all(len(c) <= 500 for c in chunks)
