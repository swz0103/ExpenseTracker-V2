import 'package:amount_input/amount_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:foundation_values/foundation_values.dart';

/// Ephemeral proposals never write a draft; only an explicit confirmation returns amounts.
class SplitAllocationDialog extends StatefulWidget {
  const SplitAllocationDialog({
    super.key,
    required this.total,
    required this.labels,
  });
  final Money total;
  final List<String> labels;
  @override
  State<SplitAllocationDialog> createState() => _SplitAllocationDialogState();
}

class _SplitAllocationDialogState extends State<SplitAllocationDialog> {
  SplitMethod _method = SplitMethod.equal;
  late final _weights = [
    for (final _ in widget.labels) TextEditingController(text: '1'),
  ];
  SplitAllocation? _proposal;
  String? _error;

  @override
  void dispose() {
    for (final controller in _weights) {
      controller.clear();
      controller.dispose();
    }
    super.dispose();
  }

  void _preview() {
    setState(() {
      _proposal = null;
      _error = null;
      try {
        _proposal = proposeSplit(
          widget.total,
          rows: widget.labels.length,
          method: _method,
          weights: _method == SplitMethod.equal
              ? const []
              : _weights.map((c) => c.text).toList(),
        );
      } on SplitAllocationException catch (e) {
        _error = switch (e.code) {
          SplitAllocationError.rowCount => '請保留 2 至 16 個拆分項目。',
          SplitAllocationError.total => '請先輸入大於 0 的交易總額。',
          SplitAllocationError.weight => '每項請填正數，最多 18 位小數；不接受算式。',
          SplitAllocationError.percentageTotal => '百分比合計必須剛好是 100%。',
          SplitAllocationError.zeroShare => '部分項目不足最小貨幣單位；請調整比例、總額或拆分數量。',
        };
      }
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('分配拆分金額'),
    scrollable: true,
    content: SizedBox(
      width: 360,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('交易總額 ${widget.total.currency.code} ${widget.total.majorText}'),
          const SizedBox(height: 16),
          DropdownButtonFormField<SplitMethod>(
            initialValue: _method,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '分配方式'),
            items: const [
              DropdownMenuItem(value: SplitMethod.equal, child: Text('平均分配')),
              DropdownMenuItem(
                value: SplitMethod.percentage,
                child: Text('百分比分配'),
              ),
              DropdownMenuItem(value: SplitMethod.ratio, child: Text('固定比例')),
            ],
            onChanged: (method) {
              if (method == null) return;
              setState(() {
                _method = method;
                _proposal = null;
                _error = null;
                for (final c in _weights) {
                  c.text = method == SplitMethod.percentage ? '' : '1';
                }
              });
            },
          ),
          if (_method != SplitMethod.equal)
            for (var i = 0; i < _weights.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('${i + 1}. ${widget.labels[i]}'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _weights[i],
                      decoration: InputDecoration(
                        labelText:
                            '${_method == SplitMethod.percentage ? "百分比" : "比例"} ${i + 1}',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        TextInputFormatter.withFunction(
                          (old, next) => next.text.length <= 128 ? next : old,
                        ),
                      ],
                      onChanged: (_) => setState(() {
                        _proposal = null;
                        _error = null;
                      }),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 16),
          const Text('每項取到最小貨幣單位，尾差依比例尾數由大到小分配，同分時前面優先。確認套用後才會更新草稿。'),
          TextButton(onPressed: _preview, child: const Text('預覽分配')),
          if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
          if (_proposal != null) ...[
            const Text('分配預覽'),
            for (var i = 0; i < widget.labels.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  '${i + 1}. ${widget.labels[i]}：'
                  '${widget.total.currency.code} ${_proposal!.amounts[i].majorText}',
                ),
              ),
            if (_proposal!.remainderMinorUnits > BigInt.zero)
              Text(
                '尾差 '
                '${widget.total.currency.code} '
                '${Money(widget.total.currency, _proposal!.remainderMinorUnits).majorText}'
                ' 已分給比例尾數最大的項目。',
              ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _proposal == null
            ? null
            : () => Navigator.of(context).pop(_proposal!.amounts),
        child: const Text('套用分配'),
      ),
    ],
  );
}
