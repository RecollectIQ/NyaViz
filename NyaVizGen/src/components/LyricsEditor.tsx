'use client';

import React, { useState, useCallback, useEffect, useRef } from 'react';
import { LyricLine, Word, formatTimeDisplay } from '@/lib/types';
import { ColorPicker } from './ColorPicker';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';

interface LyricsEditorProps {
  lines: LyricLine[];
  onUpdateLines: (lines: LyricLine[]) => void;
  currentLineIndex: number;
  isTimingMode: boolean;
  currentTime: number;
}

// Icons
const Icons = {
  check: (
    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={2}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
    </svg>
  ),
  dot: (
    <svg className="w-2 h-2" fill="currentColor" viewBox="0 0 24 24">
      <circle cx="12" cy="12" r="10" />
    </svg>
  ),
  info: (
    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M11.25 11.25l.041-.02a.75.75 0 011.063.852l-.708 2.836a.75.75 0 001.063.853l.041-.021M21 12a9 9 0 11-18 0 9 9 0 0118 0zm-9-3.75h.008v.008H12V8.25z" />
    </svg>
  ),
};

export function LyricsEditor({
  lines,
  onUpdateLines,
  currentLineIndex,
  isTimingMode,
  currentTime,
}: LyricsEditorProps) {
  const [selectedWords, setSelectedWords] = useState<Set<string>>(new Set());
  const [selectionColor, setSelectionColor] = useState<string | null>(null);
  const [rangeStartId, setRangeStartId] = useState<string | null>(null);
  const lineRefs = useRef<Map<string, HTMLDivElement>>(new Map());
  const scrollAreaRef = useRef<HTMLDivElement>(null);

  // Auto-scroll to current line when in timing mode
  useEffect(() => {
    if (isTimingMode && lines[currentLineIndex]) {
      const lineElement = lineRefs.current.get(lines[currentLineIndex].id);
      if (lineElement) {
        lineElement.scrollIntoView({
          behavior: 'smooth',
          block: 'center',
        });
      }
    }
  }, [isTimingMode, currentLineIndex, lines]);

  const handleWordClick = useCallback((wordId: string, lineId: string, shiftKey: boolean) => {
    if (isTimingMode) return;

    if (shiftKey && rangeStartId) {
      // Range selection - only include words with actual word characters
      const allWords: { id: string; lineId: string }[] = [];
      lines.forEach(line => {
        line.words.forEach(word => {
          // Only include words with word characters (not punctuation-only)
          if (word.text.trim() && /\w/.test(word.text)) {
            allWords.push({ id: word.id, lineId: line.id });
          }
        });
      });

      const startIdx = allWords.findIndex(w => w.id === rangeStartId);
      const endIdx = allWords.findIndex(w => w.id === wordId);
      
      if (startIdx !== -1 && endIdx !== -1) {
        const [from, to] = startIdx < endIdx ? [startIdx, endIdx] : [endIdx, startIdx];
        const newSelection = new Set(selectedWords);
        for (let i = from; i <= to; i++) {
          newSelection.add(allWords[i].id);
        }
        setSelectedWords(newSelection);
      }
    } else {
      // Toggle single word
      const newSelection = new Set(selectedWords);
      if (newSelection.has(wordId)) {
        newSelection.delete(wordId);
      } else {
        newSelection.add(wordId);
        setRangeStartId(wordId);
      }
      setSelectedWords(newSelection);
    }
  }, [isTimingMode, lines, selectedWords, rangeStartId]);

  const applyColorToSelection = useCallback((color: string | null) => {
    if (selectedWords.size === 0) return;

    const updatedLines = lines.map(line => ({
      ...line,
      words: line.words.map(word => ({
        ...word,
        color: selectedWords.has(word.id) ? color : word.color,
      })),
    }));

    onUpdateLines(updatedLines);
    setSelectionColor(color);
  }, [lines, onUpdateLines, selectedWords]);

  const applyStyleToSelection = useCallback((style: 'bold' | 'italic') => {
    if (selectedWords.size === 0) return;

    const updatedLines = lines.map(line => ({
      ...line,
      words: line.words.map(word => {
        if (!selectedWords.has(word.id)) return word;
        return {
          ...word,
          isBold: style === 'bold' ? !word.isBold : word.isBold,
          isItalic: style === 'italic' ? !word.isItalic : word.isItalic,
        };
      }),
    }));

    onUpdateLines(updatedLines);
  }, [lines, onUpdateLines, selectedWords]);

  const clearSelection = useCallback(() => {
    setSelectedWords(new Set());
    setRangeStartId(null);
  }, []);

  const selectAllInLine = useCallback((lineId: string) => {
    const line = lines.find(l => l.id === lineId);
    if (!line) return;

    const newSelection = new Set(selectedWords);
    line.words.forEach(word => {
      // Only select words that have actual word characters (not punctuation-only)
      if (word.text.trim() && /\w/.test(word.text)) {
        newSelection.add(word.id);
      }
    });
    setSelectedWords(newSelection);
  }, [lines, selectedWords]);

  return (
    <div className="flex flex-col h-full min-h-0">
      {/* Selection Toolbar - Fixed at top */}
      <div className="flex-shrink-0 z-10">
        <div className="flex items-center gap-3 p-3 bg-[var(--gray-850)] border-b border-[var(--border)]">
          <ColorPicker
            selectedColor={selectionColor}
            onColorSelect={applyColorToSelection}
            disabled={selectedWords.size === 0}
          />
          
          <Button
            variant="outline"
            size="icon"
            onClick={() => applyStyleToSelection('bold')}
            disabled={selectedWords.size === 0}
            className="w-9 h-9 font-bold border-[var(--border)] hover:bg-[var(--gray-700)] disabled:opacity-30"
          >
            B
          </Button>
          
          <Button
            variant="outline"
            size="icon"
            onClick={() => applyStyleToSelection('italic')}
            disabled={selectedWords.size === 0}
            className="w-9 h-9 italic border-[var(--border)] hover:bg-[var(--gray-700)] disabled:opacity-30"
          >
            I
          </Button>

          <div className="flex-1" />

          {selectedWords.size > 0 && (
            <>
              <Badge variant="secondary" className="bg-[var(--gray-700)] text-[var(--gray-300)]">
                {selectedWords.size} selected
              </Badge>
              <Button
                variant="ghost"
                size="sm"
                onClick={clearSelection}
                className="text-[var(--muted-foreground)] hover:text-[var(--foreground)] hover:bg-[var(--gray-700)]"
              >
                Clear
              </Button>
            </>
          )}
        </div>

        <div className="flex items-center gap-2 px-3 py-2 text-xs text-[var(--muted-foreground)] bg-[var(--gray-900)] border-b border-[var(--border)]">
          {Icons.info}
          <span>Click words to select. Hold Shift + Click for range. Double-click line number to select entire line.</span>
        </div>
      </div>

      {/* Lyrics Display - Scrollable */}
      <div className="flex-1 min-h-0 overflow-y-auto bg-[var(--gray-900)]" ref={scrollAreaRef}>
        <div className="p-4 space-y-1">
          {lines.map((line, idx) => {
            const isCurrentLine = idx === currentLineIndex && isTimingMode;
            const isPast = line.startTime !== null && line.endTime !== null;
            const isActive = line.startTime !== null && line.endTime === null;
            
            return (
              <div
                key={line.id}
                ref={(el) => {
                  if (el) {
                    lineRefs.current.set(line.id, el);
                  } else {
                    lineRefs.current.delete(line.id);
                  }
                }}
                className={`group flex items-start gap-3 p-3 rounded-lg transition-all ${
                  isCurrentLine 
                    ? 'line-timing bg-[var(--gray-800)]' 
                    : isActive
                    ? 'bg-[var(--gray-800)]/50 border-l-2 border-[var(--gray-500)]'
                    : isPast
                    ? 'bg-[var(--gray-850)]/50 opacity-60'
                    : 'hover:bg-[var(--gray-850)]'
                }`}
              >
                {/* Line Number & Timing */}
                <div 
                  className="flex flex-col items-center min-w-[50px] text-xs font-mono cursor-pointer"
                  onDoubleClick={() => selectAllInLine(line.id)}
                  title="Double-click to select all words"
                >
                  <span className={`${isCurrentLine ? 'text-[var(--foreground)]' : 'text-[var(--muted-foreground)]'}`}>
                    #{idx + 1}
                  </span>
                  {isPast && (
                    <span className="text-[10px] text-[var(--muted-foreground)]">
                      {formatTimeDisplay(line.startTime!)}
                    </span>
                  )}
                </div>

                {/* Words */}
                <div className="flex-1 flex flex-wrap gap-0.5 leading-relaxed">
                  {line.words.map((word) => {
                    const isSelected = selectedWords.has(word.id);
                    const isWhitespace = !word.text.trim();
                    // Check if this token is punctuation-only (no word characters)
                    const isPunctuationOnly = !isWhitespace && !/\w/.test(word.text);
                    
                    if (isWhitespace) {
                      return <span key={word.id}>{word.text}</span>;
                    }

                    // Punctuation-only tokens are not selectable, just render them
                    if (isPunctuationOnly) {
                      return (
                        <span
                          key={word.id}
                          className="select-none"
                          style={{
                            color: word.color || 'inherit',
                          }}
                        >
                          {word.text}
                        </span>
                      );
                    }

                    return (
                      <span
                        key={word.id}
                        onClick={(e) => handleWordClick(word.id, line.id, e.shiftKey)}
                        className={`
                          px-1 py-0.5 rounded cursor-pointer transition-all select-none
                          ${isSelected ? 'ring-1 ring-[var(--gray-400)] bg-[var(--gray-700)]' : 'hover:bg-[var(--gray-800)]'}
                          ${word.isBold ? 'font-bold' : ''}
                          ${word.isItalic ? 'italic' : ''}
                          ${isTimingMode ? 'pointer-events-none' : ''}
                        `}
                        style={{
                          color: word.color || 'inherit',
                        }}
                      >
                        {word.text}
                      </span>
                    );
                  })}
                </div>

                {/* Status indicators */}
                <div className="flex items-center gap-2 min-w-[20px]">
                  {isActive && (
                    <span className="text-[var(--gray-400)] pulse-active">{Icons.dot}</span>
                  )}
                  {isPast && (
                    <span className="text-[var(--gray-500)]">{Icons.check}</span>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
