'use client';

import React, { useCallback, useEffect, useState, useRef } from 'react';
import { Button } from '@/components/ui/button';
import { LyricLine, formatTimeDisplay } from '@/lib/types';

interface TimingControlsProps {
  lines: LyricLine[];
  onUpdateLines: (lines: LyricLine[]) => void;
  currentLineIndex: number;
  onLineIndexChange: (index: number) => void;
  isTimingMode: boolean;
  onTimingModeChange: (mode: boolean) => void;
  getCurrentTime: () => number;
  isAudioLoaded: boolean;
  isPlaying: boolean;
  onPlay: () => void;
}

// Icons
const Icons = {
  clock: (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M12 6v6h4.5m4.5 0a9 9 0 11-18 0 9 9 0 0118 0z" />
    </svg>
  ),
  stop: (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
    </svg>
  ),
  check: (
    <svg className="w-12 h-12" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
    </svg>
  ),
  record: (
    <svg className="w-3 h-3" fill="currentColor" viewBox="0 0 24 24">
      <circle cx="12" cy="12" r="10" />
    </svg>
  ),
};

export function TimingControls({
  lines,
  onUpdateLines,
  currentLineIndex,
  onLineIndexChange,
  isTimingMode,
  onTimingModeChange,
  getCurrentTime,
  isAudioLoaded,
  isPlaying,
  onPlay,
}: TimingControlsProps) {
  const [isPressed, setIsPressed] = useState(false);
  const [pressStartTime, setPressStartTime] = useState<number | null>(null);
  const pressStartRef = useRef<number | null>(null);

  const startTiming = useCallback(() => {
    if (!isAudioLoaded) return;
    
    // Reset all timing
    const resetLines = lines.map(line => ({
      ...line,
      startTime: null,
      endTime: null,
    }));
    onUpdateLines(resetLines);
    onLineIndexChange(0);
    onTimingModeChange(true);
    
    // Start playing if not already
    if (!isPlaying) {
      onPlay();
    }
  }, [isAudioLoaded, lines, onUpdateLines, onLineIndexChange, onTimingModeChange, isPlaying, onPlay]);

  const stopTiming = useCallback(() => {
    onTimingModeChange(false);
    setIsPressed(false);
    setPressStartTime(null);
  }, [onTimingModeChange]);

  const handlePressStart = useCallback(() => {
    if (!isTimingMode || currentLineIndex >= lines.length) return;
    
    const time = getCurrentTime();
    setIsPressed(true);
    setPressStartTime(time);
    pressStartRef.current = time;

    // Update line start time
    const updatedLines = [...lines];
    updatedLines[currentLineIndex] = {
      ...updatedLines[currentLineIndex],
      startTime: time,
      endTime: null,
    };
    onUpdateLines(updatedLines);
  }, [isTimingMode, currentLineIndex, lines, getCurrentTime, onUpdateLines]);

  const handlePressEnd = useCallback(() => {
    if (!isTimingMode || !isPressed || currentLineIndex >= lines.length) return;

    const time = getCurrentTime();
    setIsPressed(false);
    setPressStartTime(null);

    // Update line end time
    const updatedLines = [...lines];
    updatedLines[currentLineIndex] = {
      ...updatedLines[currentLineIndex],
      endTime: time,
    };
    onUpdateLines(updatedLines);

    // Move to next line
    const nextIndex = currentLineIndex + 1;
    if (nextIndex >= lines.length) {
      // All lines timed
      onTimingModeChange(false);
    } else {
      onLineIndexChange(nextIndex);
    }
  }, [isTimingMode, isPressed, currentLineIndex, lines, getCurrentTime, onUpdateLines, onLineIndexChange, onTimingModeChange]);

  // Handle keyboard events
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.code === 'Space' && isTimingMode && !isPressed) {
        e.preventDefault();
        handlePressStart();
      }
    };

    const handleKeyUp = (e: KeyboardEvent) => {
      if (e.code === 'Space' && isTimingMode && isPressed) {
        e.preventDefault();
        handlePressEnd();
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    window.addEventListener('keyup', handleKeyUp);

    return () => {
      window.removeEventListener('keydown', handleKeyDown);
      window.removeEventListener('keyup', handleKeyUp);
    };
  }, [isTimingMode, isPressed, handlePressStart, handlePressEnd]);

  const timedLinesCount = lines.filter(l => l.startTime !== null && l.endTime !== null).length;
  const progress = lines.length > 0 ? (timedLinesCount / lines.length) * 100 : 0;

  return (
    <div className="space-y-4">
      {/* Mode Controls */}
      <div className="flex items-center gap-3">
        {!isTimingMode ? (
          <Button
            onClick={startTiming}
            disabled={!isAudioLoaded || lines.length === 0}
            className="flex-1 h-12 btn-primary text-[var(--foreground)] font-medium disabled:opacity-30"
          >
            {Icons.clock}
            <span className="ml-2">Start Timing Mode</span>
          </Button>
        ) : (
          <Button
            onClick={stopTiming}
            variant="outline"
            className="flex-1 h-12 border-[var(--destructive)]/30 text-[var(--destructive)] hover:bg-[var(--destructive)]/10"
          >
            {Icons.stop}
            <span className="ml-2">Exit Timing Mode</span>
          </Button>
        )}
      </div>

      {/* Timing Button */}
      {isTimingMode && currentLineIndex < lines.length && (
        <div className="space-y-3">
          {/* Current Line Preview */}
          <div className="p-4 rounded-xl bg-[var(--gray-850)] border border-[var(--border)]">
            <div className="text-xs text-[var(--muted-foreground)] mb-1">
              Line {currentLineIndex + 1} of {lines.length}
            </div>
            <div className="text-base font-medium text-[var(--foreground)] line-clamp-2">
              {lines[currentLineIndex]?.text || ''}
            </div>
            {isPressed && pressStartTime !== null && (
              <div className="mt-2 text-sm text-[var(--gray-400)] font-mono">
                Started at: {formatTimeDisplay(pressStartTime)}
              </div>
            )}
          </div>

          {/* Big Timing Button */}
          <button
            onMouseDown={handlePressStart}
            onMouseUp={handlePressEnd}
            onMouseLeave={() => isPressed && handlePressEnd()}
            onTouchStart={(e) => {
              e.preventDefault();
              handlePressStart();
            }}
            onTouchEnd={(e) => {
              e.preventDefault();
              handlePressEnd();
            }}
            className={`
              w-full h-28 rounded-2xl font-semibold text-lg transition-all select-none
              border-2
              ${isPressed 
                ? 'bg-[var(--gray-700)] border-[var(--gray-500)] scale-[0.98]' 
                : 'bg-[var(--gray-800)] border-[var(--gray-700)] hover:bg-[var(--gray-750)] hover:border-[var(--gray-600)]'
              }
              shadow-soft
            `}
          >
            {isPressed ? (
              <div className="flex flex-col items-center gap-2 text-[var(--foreground)]">
                <div className="flex items-center gap-3">
                  <span className="text-[var(--gray-400)] pulse-active">{Icons.record}</span>
                  <span>HOLD...</span>
                </div>
                <span className="text-sm font-normal text-[var(--muted-foreground)]">Release to end line</span>
              </div>
            ) : (
              <div className="flex flex-col items-center gap-2 text-[var(--foreground)]">
                <span>PRESS & HOLD</span>
                <span className="text-sm font-normal text-[var(--muted-foreground)]">or use SPACEBAR</span>
              </div>
            )}
          </button>
        </div>
      )}

      {/* Timing Complete */}
      {isTimingMode && currentLineIndex >= lines.length && (
        <div className="p-6 rounded-xl bg-[var(--gray-850)] border border-[var(--success)]/20 text-center">
          <div className="text-[var(--success)] mb-3">
            {Icons.check}
          </div>
          <div className="text-lg font-medium text-[var(--foreground)]">All Lines Timed!</div>
          <div className="text-sm text-[var(--muted-foreground)] mt-1">
            Ready to export your NyaViz file
          </div>
        </div>
      )}

      {/* Progress */}
      {lines.length > 0 && (
        <div className="space-y-2">
          <div className="flex justify-between text-xs text-[var(--muted-foreground)]">
            <span>Progress</span>
            <span>{timedLinesCount} / {lines.length} lines</span>
          </div>
          <div className="h-1.5 rounded-full bg-[var(--gray-800)] overflow-hidden">
            <div 
              className="h-full rounded-full bg-[var(--gray-500)] transition-all duration-300"
              style={{ width: `${progress}%` }}
            />
          </div>
        </div>
      )}
    </div>
  );
}
