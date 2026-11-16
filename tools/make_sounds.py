#!/usr/bin/env python3
"""Синтезирует звуки игры (свои, без лицензий): короткие эффекты и спокойную музыку.

    python3 tools/make_sounds.py Hearthmend/Resources/Sounds

Нужны numpy и ffmpeg (перевод в .m4a, чтобы файлы были маленькими).
"""
import os, subprocess, sys, wave
import numpy as np

SR = 44100


def env(n, attack=0.005, release=None):
    t = np.arange(n) / SR
    a = np.clip(t / attack, 0, 1)
    r = np.exp(-t / release) if release else 1
    return a * r


def tone(freq, dur, wave_="sine", release=0.15, vol=0.5, bend=0.0):
    n = int(SR * dur)
    t = np.arange(n) / SR
    f = freq * (1 + bend * t / dur)
    phase = 2 * np.pi * np.cumsum(f) / SR
    if wave_ == "sine":
        s = np.sin(phase)
    elif wave_ == "tri":
        s = 2 / np.pi * np.arcsin(np.sin(phase))
    else:  # мягкий "щипок": основной тон и обертоны затухают быстрее
        s = np.sin(phase) + 0.35 * np.sin(2 * phase) * np.exp(-t / 0.08) + 0.15 * np.sin(3 * phase) * np.exp(-t / 0.05)
    return vol * s * env(n, release=release)


def mix(*parts):
    n = max(len(p) + off for p, off in parts)
    out = np.zeros(n)
    for p, off in parts:
        out[off:off + len(p)] += p
    return out


def at(sec):
    return int(sec * SR)


def save(path, data):
    data = data / max(1e-9, np.max(np.abs(data))) * 0.8
    pcm = (data * 32767).astype(np.int16)
    wav = path + ".wav"
    with wave.open(wav, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "aac", "-b:a", "96k", path + ".m4a"], check=True)
    os.remove(wav)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "Hearthmend/Resources/Sounds"
    os.makedirs(out, exist_ok=True)
    C5, D5, E5, G5, A5, C6, E6, G6 = 523.25, 587.33, 659.25, 783.99, 880.0, 1046.5, 1318.5, 1568.0

    # тап по генератору: короткий деревянный "тук" с подъемом
    save(f"{out}/spawn", mix((tone(420, 0.12, "pluck", 0.04, bend=0.6), 0), (tone(840, 0.08, "sine", 0.03, 0.2), at(0.01))))
    # слияние: два восходящих колокольчика
    save(f"{out}/merge", mix((tone(E5, 0.25, "pluck", 0.12), 0), (tone(A5, 0.35, "pluck", 0.18), at(0.07)),
                             (tone(E6, 0.3, "sine", 0.12, 0.15), at(0.07))))
    # перемещение: мягкий шорох-тык
    save(f"{out}/drop", tone(260, 0.08, "tri", 0.025, 0.6, bend=-0.3))
    # заказ отдан: монетки
    save(f"{out}/coins", mix(*[(tone(f, 0.18, "sine", 0.06, 0.4), at(i * 0.06)) for i, f in enumerate([G5 * 2, E6, G6, C6 * 2])]))
    # стройка: веселое арпеджио и аккорд
    arp = [C5, E5, G5, C6]
    save(f"{out}/build", mix(*[(tone(f, 0.3, "pluck", 0.2), at(i * 0.09)) for i, f in enumerate(arp)],
                             (tone(C5, 0.9, "tri", 0.4, 0.3), at(0.36)), (tone(E5, 0.9, "tri", 0.4, 0.3), at(0.36)),
                             (tone(G5, 0.9, "tri", 0.4, 0.3), at(0.36))))
    # новый уровень: фанфара
    save(f"{out}/levelup", mix(*[(tone(f, 0.22, "pluck", 0.15), at(i * 0.11)) for i, f in enumerate([G5, C6, E6])],
                               (tone(G6, 0.7, "sine", 0.35, 0.4), at(0.33)), (tone(C6, 0.7, "tri", 0.35, 0.3), at(0.33))))
    # ошибка / нет энергии: тихое "бум-бум" вниз
    save(f"{out}/nope", mix((tone(220, 0.12, "tri", 0.05), 0), (tone(165, 0.16, "tri", 0.07), at(0.11))))
    # пузырь лопнул / кувшин открыт: искорки
    rng = np.random.default_rng(3)
    save(f"{out}/sparkle", mix(*[(tone(float(f), 0.2, "sine", 0.08, 0.25), at(i * 0.04))
                                 for i, f in enumerate(rng.choice([C6, E6, G6, C6 * 2], 7))]))

    # музыка: спокойная пентатоника в щипках над мягкими аккордами, петля 32 такта
    bpm = 84
    beat = 60 / bpm
    chords = [[C5 / 2, E5 / 2, G5 / 2], [A5 / 4, C5 / 2, E5 / 2], [D5 / 2, G5 / 2 * 0.5 * 2, A5 / 2], [G5 / 4, D5 / 2, G5 / 2]]
    scale = [C5, D5, E5, G5, A5, C6]
    rng = np.random.default_rng(11)
    parts = []
    bars = 16
    for bar in range(bars):
        chord = chords[bar % 4]
        start = bar * 4 * beat
        for f in chord:
            parts.append((tone(f, 4 * beat, "tri", 1.6, 0.12), at(start)))
        parts.append((tone(chord[0] / 2, 4 * beat, "sine", 1.2, 0.18), at(start)))
        idx = rng.integers(0, len(scale))
        for step in range(8):
            if rng.random() < 0.55:
                idx = int(np.clip(idx + rng.integers(-2, 3), 0, len(scale) - 1))
                parts.append((tone(scale[idx], beat, "pluck", 0.35, 0.22), at(start + step * beat / 2)))
    music = mix(*parts)
    loop = at(bars * 4 * beat)
    tail = music[loop:]
    music = music[:loop]
    music[:len(tail)] += tail  # хвост последних нот переходит в начало: петля без щелчка
    save(f"{out}/music", music)
    print("готово:", sorted(os.listdir(out)))


if __name__ == "__main__":
    main()
