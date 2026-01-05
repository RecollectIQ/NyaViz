'use client';

import React, { useRef, useEffect, useState, useCallback } from 'react';
import { Button } from '@/components/ui/button';
import { Slider } from '@/components/ui/slider';
import { formatTimeDisplay } from '@/lib/types';

interface AudioPlayerProps {
  onTimeUpdate: (time: number) => void;
  onLoadedMetadata: (duration: number) => void;
  isTimingMode: boolean;
  audioRef: React.RefObject<HTMLAudioElement | null>;
}

// Icons
const Icons = {
  music: (
    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M9 9l10.5-3m0 6.553v3.75a2.25 2.25 0 01-1.632 2.163l-1.32.377a1.803 1.803 0 11-.99-3.467l2.31-.66a2.25 2.25 0 001.632-2.163zm0 0V2.25L9 5.25v10.303m0 0v3.75a2.25 2.25 0 01-1.632 2.163l-1.32.377a1.803 1.803 0 01-.99-3.467l2.31-.66A2.25 2.25 0 009 15.553z" />
    </svg>
  ),
  play: (
    <svg className="w-6 h-6 ml-0.5" fill="currentColor" viewBox="0 0 24 24">
      <path d="M8 5v14l11-7z" />
    </svg>
  ),
  pause: (
    <svg className="w-6 h-6" fill="currentColor" viewBox="0 0 24 24">
      <path d="M6 4h4v16H6V4zm8 0h4v16h-4V4z" />
    </svg>
  ),
  rewind: (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M21 16.811c0 .864-.933 1.405-1.683.977l-7.108-4.062a1.125 1.125 0 010-1.953l7.108-4.062A1.125 1.125 0 0121 8.688v8.123zM11.25 16.811c0 .864-.933 1.405-1.683.977l-7.108-4.062a1.125 1.125 0 010-1.953l7.108-4.062a1.125 1.125 0 011.683.977v8.123z" />
    </svg>
  ),
  forward: (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M3 8.688c0-.864.933-1.405 1.683-.977l7.108 4.062a1.125 1.125 0 010 1.953l-7.108 4.062A1.125 1.125 0 013 16.81V8.688zM12.75 8.688c0-.864.933-1.405 1.683-.977l7.108 4.062a1.125 1.125 0 010 1.953l-7.108 4.062a1.125 1.125 0 01-1.683-.977V8.688z" />
    </svg>
  ),
  lock: (
    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z" />
    </svg>
  ),
};

export function AudioPlayer({ 
  onTimeUpdate, 
  onLoadedMetadata,
  isTimingMode,
  audioRef
}: AudioPlayerProps) {
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [audioFile, setAudioFile] = useState<string | null>(null);
  const [fileName, setFileName] = useState<string>('');
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleFileChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      const url = URL.createObjectURL(file);
      setAudioFile(url);
      setFileName(file.name);
      setIsPlaying(false);
      setCurrentTime(0);
    }
  }, []);

  const handleTimeUpdate = useCallback(() => {
    if (audioRef.current) {
      const time = audioRef.current.currentTime * 1000; // convert to ms
      setCurrentTime(time);
      onTimeUpdate(time);
    }
  }, [audioRef, onTimeUpdate]);

  const handleLoadedMetadata = useCallback(() => {
    if (audioRef.current) {
      const dur = audioRef.current.duration * 1000; // convert to ms
      setDuration(dur);
      onLoadedMetadata(dur);
    }
  }, [audioRef, onLoadedMetadata]);

  const togglePlayPause = useCallback(() => {
    if (audioRef.current) {
      if (isPlaying) {
        audioRef.current.pause();
      } else {
        audioRef.current.play();
      }
      setIsPlaying(!isPlaying);
    }
  }, [audioRef, isPlaying]);

  const handleSeek = useCallback((value: number[]) => {
    if (audioRef.current && !isTimingMode) {
      const time = value[0];
      audioRef.current.currentTime = time / 1000;
      setCurrentTime(time);
    }
  }, [audioRef, isTimingMode]);

  const handleEnded = useCallback(() => {
    setIsPlaying(false);
  }, []);

  const handlePlay = useCallback(() => {
    setIsPlaying(true);
  }, []);

  const handlePause = useCallback(() => {
    setIsPlaying(false);
  }, []);

  useEffect(() => {
    const audio = audioRef.current;
    if (audio) {
      audio.addEventListener('timeupdate', handleTimeUpdate);
      audio.addEventListener('loadedmetadata', handleLoadedMetadata);
      audio.addEventListener('ended', handleEnded);
      audio.addEventListener('play', handlePlay);
      audio.addEventListener('pause', handlePause);
      
      return () => {
        audio.removeEventListener('timeupdate', handleTimeUpdate);
        audio.removeEventListener('loadedmetadata', handleLoadedMetadata);
        audio.removeEventListener('ended', handleEnded);
        audio.removeEventListener('play', handlePlay);
        audio.removeEventListener('pause', handlePause);
      };
    }
  }, [audioRef, handleTimeUpdate, handleLoadedMetadata, handleEnded, handlePlay, handlePause]);

  return (
    <div className="space-y-4">
      <audio ref={audioRef} src={audioFile || undefined} />
      
      {/* File Upload */}
      <div className="flex items-center gap-4">
        <input
          ref={fileInputRef}
          type="file"
          accept="audio/*"
          onChange={handleFileChange}
          className="hidden"
        />
        <Button
          onClick={() => fileInputRef.current?.click()}
          variant="outline"
          className="border-[var(--border)] hover:border-[var(--gray-600)] hover:bg-[var(--gray-800)] transition-all"
        >
          {Icons.music}
          <span className="ml-2">{audioFile ? 'Change Audio' : 'Load Audio'}</span>
        </Button>
        {fileName && (
          <span className="text-sm text-[var(--muted-foreground)] font-mono truncate max-w-[180px]">
            {fileName}
          </span>
        )}
      </div>

      {/* Player Controls */}
      {audioFile && (
        <div className="p-4 rounded-xl bg-[var(--gray-850)] border border-[var(--border)] shadow-soft">
          {/* Progress Bar */}
          <div className="mb-4">
            <Slider
              value={[currentTime]}
              max={duration || 100}
              step={100}
              onValueChange={handleSeek}
              disabled={isTimingMode}
              className={isTimingMode ? 'opacity-50 cursor-not-allowed' : ''}
            />
            <div className="flex justify-between text-xs text-[var(--muted-foreground)] mt-2 font-mono">
              <span>{formatTimeDisplay(currentTime)}</span>
              <span>{formatTimeDisplay(duration)}</span>
            </div>
          </div>

          {/* Playback Controls */}
          <div className="flex items-center justify-center gap-3">
            <Button
              onClick={() => {
                if (audioRef.current && !isTimingMode) {
                  audioRef.current.currentTime = Math.max(0, audioRef.current.currentTime - 5);
                }
              }}
              variant="ghost"
              size="icon"
              disabled={isTimingMode}
              className="w-10 h-10 hover:bg-[var(--gray-700)] disabled:opacity-30"
            >
              {Icons.rewind}
            </Button>
            
            <Button
              onClick={togglePlayPause}
              size="icon"
              className={`w-14 h-14 rounded-full btn-primary transition-all ${isPlaying ? 'ring-2 ring-[var(--gray-500)]' : ''}`}
            >
              {isPlaying ? Icons.pause : Icons.play}
            </Button>
            
            <Button
              onClick={() => {
                if (audioRef.current && !isTimingMode) {
                  audioRef.current.currentTime = Math.min(audioRef.current.duration, audioRef.current.currentTime + 5);
                }
              }}
              variant="ghost"
              size="icon"
              disabled={isTimingMode}
              className="w-10 h-10 hover:bg-[var(--gray-700)] disabled:opacity-30"
            >
              {Icons.forward}
            </Button>
          </div>

          {isTimingMode && (
            <div className="mt-3 flex items-center justify-center gap-2 text-xs text-[var(--muted-foreground)]">
              {Icons.lock}
              <span>Timing mode active — seeking disabled</span>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
