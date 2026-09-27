part of 'main.dart';

extension _EntryNoteEditor on _PreviewHomeState {
  Future<void> _startNote(PublicId id) => _perform(() async {
    if (_entryDraft != null || _draftUnreadable) throw DraftNeedsResolution();
    final note = await _engine!.entryNote(id);
    if (!mounted || !_engine!.isUnlocked) return;
    _edit(_Page.posting);
    _changeNote(() {
      _noteTarget = id;
      _noteRevision = note.revision;
      _noteText.text = note.text;
    });
  });

  void _resumeNote(EntryDraft draft) {
    _edit(_Page.posting);
    _changeNote(() {
      _entryDraft = draft;
      _noteTarget = draft.fields.noteOf;
      _noteRevision = draft.fields.noteRevision;
      _noteText.text = draft.fields.noteText;
    });
  }

  List<Widget> _noteInputs() => [
    Text('編輯備註', style: Theme.of(context).textTheme.headlineSmall),
    const Text('修改備註不影響餘額。清空後儲存會保留清除紀錄。'),
    const SizedBox(height: 16),
    TextField(
      key: const Key('note-text'),
      controller: _noteText,
      enabled: !_busy && !_postingFrozen,
      minLines: 3,
      maxLines: 8,
      // Limit by Unicode scalar count, matching the portable domain contract.
      inputFormatters: [
        TextInputFormatter.withFunction(
          (old, next) =>
              next.text.runes.length <= NoteChange.maxCharacters &&
                  !next.text.runes.any(
                    (r) => r == 0 || (r >= 0xd800 && r <= 0xdfff),
                  )
              ? next
              : old,
        ),
      ],
      decoration: const InputDecoration(
        labelText: '備註',
        helperText: '最多 1024 個字元',
      ),
      onChanged: (_) => _queueDraft(),
    ),
    TextButton(
      onPressed: _busy
          ? null
          : () => _perform(() async {
              if (!_postingFrozen) {
                _queueDraft();
                await _draftSaveTail;
                if (_draftSaveError != null) throw _draftSaveError!;
              }
              final saved = await _engine!.refreshNoteDraft();
              if (!mounted || !_engine!.isUnlocked) return;
              _changeNote(() {
                _entryDraft = saved;
                _noteRevision = saved.fields.noteRevision;
                _message = '已讀取最新版本，保留你的草稿；請確認後再儲存。';
              });
            }),
      child: const Text('讀取最新版本並保留草稿'),
    ),
    TextButton(
      onPressed: _busy ? null : () => _showActivity(_noteTarget!),
      child: const Text('查看活動'),
    ),
  ];

  List<Widget> _noteSummary(LedgerEntry entry) => [
    if (entry.note.text.isNotEmpty)
      Text(
        _privacy == PrivacyMode.hidden ? '備註已隱藏' : entry.note.text,
        key: ValueKey('entry-note-${entry.id}'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        key: ValueKey('entry-note-edit-${entry.id}'),
        onPressed: _busy ? null : () => _startNote(entry.id),
        child: const Text('編輯備註'),
      ),
    ),
  ];
}
