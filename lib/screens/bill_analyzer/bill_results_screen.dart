// lib/screens/bill_analyzer/bill_results_screen.dart
import 'package:flutter/material.dart';
import '../../models/bill_analysis_model.dart';
import '../../services/bill_analyzer_service.dart';
import '../../screens/bill_analyzer/bill_history_screen.dart';

class BillResultsScreen extends StatefulWidget {
  final BillAnalysis analysis;

  const BillResultsScreen({
    super.key,
    required this.analysis,
  });

  @override
  State<BillResultsScreen> createState() => _BillResultsScreenState();
}

class _BillResultsScreenState extends State<BillResultsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _chatController = TextEditingController();
  final List<ChatMessage> _chatMessages = [];
  final BillAnalyzerService _service = BillAnalyzerService.instance;
  bool _isChatLoading = false;
  bool _historyLoaded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadChatHistory(); // Load existing chat history
  }

  @override
  void dispose() {
    _tabController.dispose();
    _chatController.dispose();
    super.dispose();
  }

  /// Load chat history from Firestore
  Future<void> _loadChatHistory() async {
    if (_historyLoaded) return;

    try {
      final history = await _service.getChatHistory(widget.analysis.id);

      setState(() {
        _chatMessages.clear();

        // Add welcome message
        _chatMessages.add(
          ChatMessage(
            text: '👋 Hi! I\'ve analyzed your bill. Ask me anything about the charges, medicines, or savings!',
            isUser: false,
          ),
        );

        // Add historical messages
        for (var msg in history) {
          _chatMessages.add(ChatMessage(text: msg.question, isUser: true));
          _chatMessages.add(ChatMessage(text: msg.answer, isUser: false));
        }

        _historyLoaded = true;
      });

      debugPrint('✅ Loaded ${history.length} chat messages from history');
    } catch (e) {
      debugPrint('⚠️ Error loading chat history: $e');
      // Still show welcome message
      _addWelcomeMessage();
    }
  }

  void _addWelcomeMessage() {
    if (_chatMessages.isEmpty) {
      _chatMessages.add(
        ChatMessage(
          text: '👋 Hi! I\'ve analyzed your bill. Ask me anything about the charges, medicines, or savings!',
          isUser: false,
        ),
      );
    }
  }

  Future<void> _sendChatMessage() async {
    final question = _chatController.text.trim();
    if (question.isEmpty || _isChatLoading) return;

    setState(() {
      _chatMessages.add(ChatMessage(text: question, isUser: true));
      _chatController.clear();
      _isChatLoading = true;
    });

    try {
      final answer = await _service.chatAboutBill(
        analysis: widget.analysis,
        question: question,
      );

      setState(() {
        _chatMessages.add(ChatMessage(text: answer, isUser: false));
      });
    } catch (e) {
      setState(() {
        _chatMessages.add(
          ChatMessage(
            text: 'Sorry, I encountered an error. Please try again.',
            isUser: false,
          ),
        );
      });
    } finally {
      setState(() {
        _isChatLoading = false;
      });
    }
  }

  Future<void> _clearChatHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: const Text('Clear Chat History?'),
            content: const Text(
              'This will delete all your questions and answers about this bill. This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Clear'),
              ),
            ],
          ),
    );

    if (confirm == true) {
      try {
        await _service.clearChatHistory(widget.analysis.id);
        setState(() {
          _chatMessages.clear();
          _addWelcomeMessage();
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chat history cleared')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to clear history')),
          );
        }
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bill Analysis'),
        backgroundColor: const Color(0xFF00C896),
        foregroundColor: Colors.white,
        actions: [
          // Add clear chat history button when on chat tab
          if (_tabController.index == 2)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Clear Chat History',
              onPressed: _clearChatHistory,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          onTap: (_) => setState(() {}), // Rebuild to show/hide clear button
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Items'),
            Tab(text: 'Chat'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildItemsTab(),
          _buildChatTab(),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // OVERVIEW TAB
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryCard(),
          const SizedBox(height: 16),
          if (widget.analysis.flags.isNotEmpty) _buildFlagsSection(),
          if (widget.analysis.flags.isNotEmpty) const SizedBox(height: 16),
          _buildTotalCard(),
          const SizedBox(height: 16),
          if (widget.analysis.suggestions.isNotEmpty) _buildSuggestionsCard(),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C896).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.analytics,
                    color: Color(0xFF00C896),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.analysis.pharmacyName ?? 'Medical Bill',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (widget.analysis.billDate != null)
                        Text(
                          widget.analysis.billDate!,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              widget.analysis.summary,
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlagsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              const Icon(Icons.flag, color: Color(0xFFF59E0B)),
              const SizedBox(width: 8),
              Text(
                'Issues Detected (${widget.analysis.flags.length})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...widget.analysis.flags.map((flag) => _buildFlagCard(flag)).toList(),
      ],
    );
  }

  Widget _buildFlagCard(BillFlag flag) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: flag.severityColor.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: flag.severityColor.withOpacity(0.3), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(flag.severityIcon, color: flag.severityColor, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    flag.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: flag.severityColor,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: flag.severityColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    flag.severity.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              flag.description,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
            if (flag.affectedItems.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: flag.affectedItems
                    .map((item) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    item,
                    style: const TextStyle(fontSize: 12),
                  ),
                ))
                    .toList(),
              ),
            ],
            if (flag.potentialSavings != null && flag.potentialSavings! > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.savings, color: Color(0xFF10B981), size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Potential savings: RM ${flag.potentialSavings!.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTotalCard() {
    return Card(
      color: const Color(0xFF00C896),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Subtotal',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                ),
                Text(
                  'RM ${widget.analysis.subtotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (widget.analysis.tax != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Tax',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                  Text(
                    'RM ${widget.analysis.tax!.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            const Divider(color: Colors.white30),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total Amount',
                  style: TextStyle(
                    fontSize: 20,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'RM ${widget.analysis.totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 24,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (widget.analysis.potentialTotalSavings != null &&
                widget.analysis.potentialTotalSavings! > 0) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.savings, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'You could save RM ${widget.analysis.potentialTotalSavings!.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.lightbulb, color: Color(0xFFF59E0B)),
                SizedBox(width: 8),
                Text(
                  'Suggestions',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...widget.analysis.suggestions.asMap().entries.map((entry) {
              final index = entry.key;
              final suggestion = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Color(0xFFF59E0B),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        suggestion,
                        style: const TextStyle(fontSize: 15, height: 1.5),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ITEMS TAB
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildItemsTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: widget.analysis.items.length,
      itemBuilder: (context, index) {
        final item = widget.analysis.items[index];
        return _buildItemCard(item);
      },
    );
  }

  Widget _buildItemCard(BillItem item) {
    final isPriceNormal = item.isPriceNormal ?? true;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isPriceNormal
              ? Colors.grey[300]!
              : const Color(0xFFF59E0B).withOpacity(0.3),
          width: isPriceNormal ? 1 : 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (item.category != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00C896).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.category!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF00C896),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'RM ${item.totalPrice.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isPriceNormal ? Colors.black : const Color(0xFFF59E0B),
                      ),
                    ),
                    Text(
                      '${item.quantity}x RM ${item.price.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (item.description != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFF3B82F6), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.description!,
                        style: const TextStyle(fontSize: 14, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (item.priceWarning != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber, color: Color(0xFFF59E0B), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.priceWarning!,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF92400E),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (item.alternativeSuggestion != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFD1FAE5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.savings, color: Color(0xFF10B981), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.alternativeSuggestion!,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF065F46),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CHAT TAB
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildChatTab() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _chatMessages.length,
            itemBuilder: (context, index) {
              final message = _chatMessages[index];
              return _buildChatBubble(message);
            },
          ),
        ),
        if (_isChatLoading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('AI is thinking...'),
              ],
            ),
          ),
        _buildChatInput(),
      ],
    );
  }

  Widget _buildChatBubble(ChatMessage message) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: message.isUser
              ? const Color(0xFF00C896)
              : Colors.grey[200],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: message.isUser ? Colors.white : Colors.black87,
            fontSize: 15,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildChatInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _chatController,
              decoration: InputDecoration(
                hintText: 'Ask about this bill...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[200],
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              onSubmitted: (_) => _sendChatMessage(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _sendChatMessage,
            icon: const Icon(Icons.send),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF00C896),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;

  ChatMessage({required this.text, required this.isUser});
}