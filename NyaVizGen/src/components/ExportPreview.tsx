'use client';

import React, { useState, useCallback, useEffect, useRef } from 'react';
import { Button } from '@/components/ui/button';
import { LyricLine, formatTimeDisplay } from '@/lib/types';

interface ExportPreviewProps {
  lines: LyricLine[];
  onUpdateLines: (lines: LyricLine[]) => void;
  onExport: () => void;
  onClose: () => void;
  audioRef: React.RefObject<HTMLAudioElement | null>;
  duration: number;
}

// Icons
const Icons = {
  download: (
    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5M16.5 12L12 16.5m0 0L7.5 12m4.5 4.5V3" />
    </svg>
  ),
  close: (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
    </svg>
  ),
  zoomIn: (
    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607zM10.5 7.5v6m3-3h-6" />
    </svg>
  ),
  zoomOut: (
    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607zM13.5 10.5h-6" />
    </svg>
  ),
  play: (
    <svg className="w-3 h-3" fill="currentColor" viewBox="0 0 24 24">
      <path d="M8 5v14l11-7z" />
    </svg>
  ),
  flag: (
    <svg className="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={2}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M3 3v1.5M3 21v-6m0 0l2.77-.693a9 9 0 016.208.682l.108.054a9 9 0 006.086.71l3.114-.732a48.524 48.524 0 01-.005-10.499l-3.11.732a9 9 0 01-6.085-.711l-.108-.054a9 9 0 00-6.208-.682L3 4.5M3 15V4.5" />
    </svg>
  ),
};

export function ExportPreview({
  lines,
  onUpdateLines,
  onExport,
  onClose,
  audioRef,
  duration,
}: ExportPreviewProps) {
  const [selectedLineId, setSelectedLineId] = useState<string | null>(null);
  const [currentTime, setCurrentTime] = useState(0);
  const [zoom, setZoom] = useState(1); // 1 = fit all, higher = more zoom
  const [scrollOffset, setScrollOffset] = useState(0);
  const [dragState, setDragState] = useState<{
    lineId: string;
    edge: 'start' | 'end' | 'both';
    initialStartTime: number;
    initialEndTime: number;
    initialMouseX: number;
  } | null>(null);
  
  const timelineRef = useRef<HTMLDivElement>(null);
  const playTimeoutRef = useRef<NodeJS.Timeout | null>(null);

  const timedLines = lines.filter(l => l.startTime !== null && l.endTime !== null);
  const markedCount = timedLines.filter(l => l.markedForReview).length;

  // Timeline dimensions
  const timelineWidth = duration * zoom * 0.1; // pixels per ms scaled by zoom
  const viewportWidth = timelineRef.current?.clientWidth || 800;

  // Update current time from audio
  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) return;

    const handleTimeUpdate = () => {
      setCurrentTime(audio.currentTime * 1000);
    };

    audio.addEventListener('timeupdate', handleTimeUpdate);
    return () => audio.removeEventListener('timeupdate', handleTimeUpdate);
  }, [audioRef]);

  // Play only the selected line's duration
  const handlePlayLine = useCallback((line: LyricLine) => {
    const audio = audioRef.current;
    if (!audio || line.startTime === null || line.endTime === null) return;

    // Clear any existing timeout
    if (playTimeoutRef.current) {
      clearTimeout(playTimeoutRef.current);
      playTimeoutRef.current = null;
    }

    // Pause first, then seek and play
    audio.pause();
    audio.currentTime = line.startTime / 1000;
    
    // Use promise to handle play properly
    const playPromise = audio.play();
    if (playPromise !== undefined) {
      playPromise
        .then(() => {
          // Stop at end time
          const playDuration = line.endTime! - line.startTime!;
          playTimeoutRef.current = setTimeout(() => {
            audio.pause();
          }, playDuration);
        })
        .catch(() => {
          // Ignore AbortError - happens when play is interrupted
        });
    }
  }, [audioRef]);

  // Cleanup timeout on unmount
  useEffect(() => {
    return () => {
      if (playTimeoutRef.current) {
        clearTimeout(playTimeoutRef.current);
      }
    };
  }, []);

  // Handle drag start
  const handleDragStart = useCallback((
    e: React.MouseEvent,
    lineId: string,
    edge: 'start' | 'end' | 'both'
  ) => {
    e.preventDefault();
    e.stopPropagation();
    const line = lines.find(l => l.id === lineId);
    if (!line || line.startTime === null || line.endTime === null) return;
    
    setDragState({
      lineId,
      edge,
      initialStartTime: line.startTime,
      initialEndTime: line.endTime,
      initialMouseX: e.clientX,
    });
  }, [lines]);

  // Handle drag move
  useEffect(() => {
    if (!dragState) return;

    const handleMouseMove = (e: MouseEvent) => {
      const timelineEl = timelineRef.current;
      if (!timelineEl) return;
      
      const timelineWidth = timelineEl.scrollWidth;
      const deltaX = e.clientX - dragState.initialMouseX;
      const deltaTime = (deltaX / timelineWidth) * duration;

      const updatedLines = lines.map(line => {
        if (line.id !== dragState.lineId) return line;
        
        if (dragState.edge === 'start') {
          const newStart = Math.max(0, dragState.initialStartTime + deltaTime);
          const maxStart = dragState.initialEndTime - 100;
          return { ...line, startTime: Math.min(newStart, maxStart) };
        } else if (dragState.edge === 'end') {
          const newEnd = Math.min(duration, dragState.initialEndTime + deltaTime);
          const minEnd = dragState.initialStartTime + 100;
          return { ...line, endTime: Math.max(newEnd, minEnd) };
        } else {
          // Move both (drag whole block)
          const lineDuration = dragState.initialEndTime - dragState.initialStartTime;
          let newStart = dragState.initialStartTime + deltaTime;
          let newEnd = dragState.initialEndTime + deltaTime;
          
          // Clamp to timeline bounds
          if (newStart < 0) {
            newStart = 0;
            newEnd = lineDuration;
          }
          if (newEnd > duration) {
            newEnd = duration;
            newStart = duration - lineDuration;
          }
          
          return { ...line, startTime: newStart, endTime: newEnd };
        }
      });
      onUpdateLines(updatedLines);
    };

    const handleMouseUp = () => {
      setDragState(null);
    };

    window.addEventListener('mousemove', handleMouseMove);
    window.addEventListener('mouseup', handleMouseUp);

    return () => {
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('mouseup', handleMouseUp);
    };
  }, [dragState, lines, onUpdateLines, duration]);

  // Toggle mark
  const toggleMark = useCallback((lineId: string) => {
    const updatedLines = lines.map(line => 
      line.id === lineId 
        ? { ...line, markedForReview: !line.markedForReview }
        : line
    );
    onUpdateLines(updatedLines);
  }, [lines, onUpdateLines]);

  // Adjust timing with +/- buttons
  const handleTimeAdjust = useCallback((lineId: string, field: 'startTime' | 'endTime', delta: number) => {
    const updatedLines = lines.map(line => {
      if (line.id !== lineId) return line;
      
      const currentValue = line[field];
      if (currentValue === null) return line;
      
      let newValue = currentValue + delta;
      
      // Clamp values
      if (field === 'startTime') {
        newValue = Math.max(0, Math.min(newValue, (line.endTime || duration) - 100));
      } else {
        newValue = Math.max((line.startTime || 0) + 100, Math.min(newValue, duration));
      }
      
      return { ...line, [field]: newValue };
    });
    onUpdateLines(updatedLines);
  }, [lines, onUpdateLines, duration]);

  // Zoom controls
  const handleZoomIn = () => setZoom(prev => Math.min(prev * 1.5, 10));
  const handleZoomOut = () => setZoom(prev => Math.max(prev / 1.5, 0.5));

  // Get position for a time value
  const getPosition = (time: number) => (time / duration) * 100;

  return (
    <div className="fixed inset-0 z-50 bg-[var(--gray-950)] flex flex-col">
      {/* Header */}
      <div className="flex-shrink-0 flex items-center justify-between px-4 py-3 border-b border-[var(--border)] bg-[var(--gray-900)]">
        <div className="flex items-center gap-4">
          <h2 className="text-lg font-medium text-[var(--foreground)]">Timeline Editor</h2>
          <span className="text-sm text-[var(--muted-foreground)]">
            {timedLines.length} lines
            {markedCount > 0 && <span className="text-[#ef4444] ml-2">({markedCount} flagged)</span>}
          </span>
        </div>
        <div className="flex items-center gap-2">
          <Button onClick={onExport} size="sm" className="btn-primary text-[var(--foreground)]">
            {Icons.download}
            <span className="ml-1.5">Export</span>
          </Button>
          <Button variant="ghost" size="icon" onClick={onClose} className="w-8 h-8 hover:bg-[var(--gray-800)]">
            {Icons.close}
          </Button>
        </div>
      </div>

      {/* Timeline Controls */}
      <div className="flex-shrink-0 flex items-center gap-2 px-4 py-2 border-b border-[var(--border)] bg-[var(--gray-850)]">
        <Button variant="ghost" size="icon" onClick={handleZoomOut} className="w-7 h-7 hover:bg-[var(--gray-700)]">
          {Icons.zoomOut}
        </Button>
        <div className="w-20 text-center text-xs text-[var(--muted-foreground)]">
          {Math.round(zoom * 100)}%
        </div>
        <Button variant="ghost" size="icon" onClick={handleZoomIn} className="w-7 h-7 hover:bg-[var(--gray-700)]">
          {Icons.zoomIn}
        </Button>
        <div className="flex-1" />
        <span className="text-xs text-[var(--muted-foreground)]">
          Drag block to move • Drag edges to resize • ±100ms with buttons
        </span>
      </div>

      {/* Timeline */}
      <div className="flex-shrink-0 h-24 border-b border-[var(--border)] bg-[var(--gray-900)] overflow-x-auto" ref={timelineRef}>
        <div 
          className="relative h-full"
          style={{ width: `${Math.max(100, zoom * 100)}%`, minWidth: '100%' }}
        >
          {/* Time markers */}
          <div className="absolute inset-x-0 top-0 h-5 border-b border-[var(--border)] flex">
            {Array.from({ length: Math.ceil(duration / 10000) + 1 }).map((_, i) => (
              <div 
                key={i} 
                className="absolute text-[10px] text-[var(--muted-foreground)] font-mono"
                style={{ left: `${getPosition(i * 10000)}%` }}
              >
                {formatTimeDisplay(i * 10000)}
              </div>
            ))}
          </div>

          {/* Blocks */}
          <div className="absolute inset-x-0 top-6 bottom-2 px-1">
            {timedLines.map((line, idx) => {
              const left = getPosition(line.startTime!);
              const width = getPosition(line.endTime!) - left;
              const isSelected = selectedLineId === line.id;
              const isMarked = line.markedForReview;
              const isDragging = dragState?.lineId === line.id;
              
              return (
                <div
                  key={line.id}
                  onClick={() => setSelectedLineId(line.id)}
                  className={`absolute top-0 bottom-0 rounded group transition-colors ${
                    isMarked 
                      ? 'bg-[#ef4444]/50' 
                      : isSelected
                      ? 'bg-[var(--gray-500)]'
                      : 'bg-[var(--gray-600)] hover:bg-[var(--gray-500)]'
                  } ${isSelected ? 'ring-2 ring-white z-10' : ''} ${isDragging ? 'opacity-80' : ''}`}
                  style={{ 
                    left: `${left}%`, 
                    width: `${Math.max(width, 0.5)}%`,
                  }}
                >
                  {/* Left drag handle (resize) */}
                  <div
                    onMouseDown={(e) => handleDragStart(e, line.id, 'start')}
                    className="absolute left-0 top-0 bottom-0 w-2 cursor-ew-resize hover:bg-white/40 rounded-l z-10"
                  />
                  
                  {/* Middle area (move whole block) */}
                  <div 
                    onMouseDown={(e) => handleDragStart(e, line.id, 'both')}
                    className="absolute left-2 right-2 top-0 bottom-0 cursor-grab active:cursor-grabbing flex items-center justify-center overflow-hidden"
                  >
                    <span className="text-[10px] text-white/80 truncate pointer-events-none">
                      {idx + 1}
                    </span>
                  </div>

                  {/* Right drag handle (resize) */}
                  <div
                    onMouseDown={(e) => handleDragStart(e, line.id, 'end')}
                    className="absolute right-0 top-0 bottom-0 w-2 cursor-ew-resize hover:bg-white/40 rounded-r z-10"
                  />

                  {/* Mark indicator */}
                  {isMarked && (
                    <div className="absolute -top-1 -right-1 w-3 h-3 bg-[#ef4444] rounded-full flex items-center justify-center pointer-events-none">
                      <span className="text-[8px] text-white">!</span>
                    </div>
                  )}
                </div>
              );
            })}
          </div>

          {/* Playhead */}
          <div 
            className="absolute top-5 bottom-0 w-0.5 bg-white pointer-events-none z-20"
            style={{ left: `${getPosition(currentTime)}%` }}
          >
            <div className="absolute -top-1 left-1/2 -translate-x-1/2 w-2 h-2 bg-white rotate-45" />
          </div>
        </div>
      </div>

      {/* Lines list */}
      <div className="flex-1 overflow-y-auto">
        <table className="w-full text-sm">
          <thead className="sticky top-0 bg-[var(--gray-850)] border-b border-[var(--border)]">
            <tr className="text-left text-[var(--muted-foreground)]">
              <th className="w-10 px-3 py-2 font-medium">#</th>
              <th className="w-32 px-3 py-2 font-medium">Start</th>
              <th className="w-32 px-3 py-2 font-medium">End</th>
              <th className="w-16 px-3 py-2 font-medium">Len</th>
              <th className="px-3 py-2 font-medium">Lyrics</th>
              <th className="w-16 px-3 py-2 font-medium"></th>
            </tr>
          </thead>
          <tbody>
            {timedLines.map((line, idx) => {
              const isSelected = selectedLineId === line.id;
              const isMarked = line.markedForReview;
              const lineDuration = line.endTime! - line.startTime!;
              
              return (
                <tr
                  key={line.id}
                  onClick={() => setSelectedLineId(line.id)}
                  className={`border-b border-[var(--border)] cursor-pointer transition-colors ${
                    isMarked 
                      ? 'bg-[#ef4444]/10' 
                      : isSelected
                      ? 'bg-[var(--gray-800)]'
                      : 'hover:bg-[var(--gray-850)]'
                  }`}
                >
                  <td className="px-3 py-2 font-mono text-[var(--muted-foreground)]">{idx + 1}</td>
                  <td className="px-3 py-2">
                    <div className="flex items-center gap-1">
                      <button
                        onClick={(e) => { e.stopPropagation(); handleTimeAdjust(line.id, 'startTime', -100); }}
                        className="w-5 h-5 rounded bg-[var(--gray-700)] hover:bg-[var(--gray-600)] text-xs flex items-center justify-center"
                      >
                        −
                      </button>
                      <span className="font-mono text-xs w-12 text-center">{formatTimeDisplay(line.startTime!)}</span>
                      <button
                        onClick={(e) => { e.stopPropagation(); handleTimeAdjust(line.id, 'startTime', 100); }}
                        className="w-5 h-5 rounded bg-[var(--gray-700)] hover:bg-[var(--gray-600)] text-xs flex items-center justify-center"
                      >
                        +
                      </button>
                    </div>
                  </td>
                  <td className="px-3 py-2">
                    <div className="flex items-center gap-1">
                      <button
                        onClick={(e) => { e.stopPropagation(); handleTimeAdjust(line.id, 'endTime', -100); }}
                        className="w-5 h-5 rounded bg-[var(--gray-700)] hover:bg-[var(--gray-600)] text-xs flex items-center justify-center"
                      >
                        −
                      </button>
                      <span className="font-mono text-xs w-12 text-center">{formatTimeDisplay(line.endTime!)}</span>
                      <button
                        onClick={(e) => { e.stopPropagation(); handleTimeAdjust(line.id, 'endTime', 100); }}
                        className="w-5 h-5 rounded bg-[var(--gray-700)] hover:bg-[var(--gray-600)] text-xs flex items-center justify-center"
                      >
                        +
                      </button>
                    </div>
                  </td>
                  <td className="px-3 py-2 font-mono text-[var(--muted-foreground)]">{(lineDuration / 1000).toFixed(1)}s</td>
                  <td className={`px-3 py-2 truncate max-w-md ${isMarked ? 'text-[#ef4444]' : ''}`}>
                    {line.words.map(w => w.text).join('')}
                  </td>
                  <td className="px-3 py-2">
                    <div className="flex items-center gap-1">
                      <button
                        onClick={(e) => { e.stopPropagation(); handlePlayLine(line); }}
                        className="w-6 h-6 rounded flex items-center justify-center hover:bg-[var(--gray-700)] transition-colors"
                        title="Play this line"
                      >
                        {Icons.play}
                      </button>
                      <button
                        onClick={(e) => { e.stopPropagation(); toggleMark(line.id); }}
                        className={`w-6 h-6 rounded flex items-center justify-center transition-colors ${
                          isMarked ? 'text-[#ef4444] bg-[#ef4444]/20' : 'hover:bg-[var(--gray-700)]'
                        }`}
                        title="Toggle flag"
                      >
                        {Icons.flag}
                      </button>
                    </div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {/* Status bar */}
      <div className="flex-shrink-0 px-4 py-2 border-t border-[var(--border)] bg-[var(--gray-900)] text-xs text-[var(--muted-foreground)]">
        <div className="flex items-center gap-4">
          <span>Total: {formatTimeDisplay(duration)}</span>
          {selectedLineId && (
            <span>Selected: Line {timedLines.findIndex(l => l.id === selectedLineId) + 1}</span>
          )}
        </div>
      </div>
    </div>
  );
}
