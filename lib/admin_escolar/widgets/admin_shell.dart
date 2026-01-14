// lib/admin_escolar/widgets/admin_shell.dart
import 'package:flutter/material.dart';

/// AdminShell: layout con sidebar persistente (izquierda) y área de contenido (derecha).
/// Ahora soporta un ValueNotifier<int> controller para sincronizar el índice desde fuera.
class AdminShell extends StatefulWidget {
  final List<Widget> pages;
  final List<NavItem> navItems;
  final int initialIndex;
  final double sidebarWidth;
  final ValueNotifier<int>? controller;

  const AdminShell({
    Key? key,
    required this.pages,
    required this.navItems,
    this.initialIndex = 0,
    this.sidebarWidth = 260,
    this.controller,
  }) : super(key: key);

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  late int _currentIndex;
  VoidCallback? _controllerListener;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.controller?.value ?? widget.initialIndex;
    if (widget.controller != null) {
      _controllerListener = () {
        if (mounted) {
          setState(() {
            _currentIndex = widget.controller!.value;
          });
        }
      };
      widget.controller!.addListener(_controllerListener!);
    }
  }

  @override
  void didUpdateWidget(covariant AdminShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // rehook listener if controller instance changed
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller != null && _controllerListener != null) {
        oldWidget.controller!.removeListener(_controllerListener!);
      }
      _controllerListener = null;
      if (widget.controller != null) {
        _controllerListener = () {
          if (mounted) {
            setState(() {
              _currentIndex = widget.controller!.value;
            });
          }
        };
        widget.controller!.addListener(_controllerListener!);
        _currentIndex = widget.controller!.value;
      }
    }
  }

  @override
  void dispose() {
    if (widget.controller != null && _controllerListener != null) {
      widget.controller!.removeListener(_controllerListener!);
    }
    super.dispose();
  }

  void _selectIndex(int idx) {
    if (widget.controller != null) {
      widget.controller!.value = idx;
    } else {
      setState(() => _currentIndex = idx);
    }
    if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 920;
    final sidebar = _buildSidebar();

    return Scaffold(
      appBar: isWide ? null : AppBar(title: Text(widget.navItems[_currentIndex].label), backgroundColor: Colors.blue.shade900),
      drawer: isWide ? null : Drawer(child: sidebar),
      body: Row(
        children: [
          if (isWide) SizedBox(width: widget.sidebarWidth, child: sidebar),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: widget.pages,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      color: const Color(0xFFF2F6F4),
      child: Column(
        children: [
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                CircleAvatar(radius: 20, backgroundColor: Colors.orange, child: const Icon(Icons.school, color: Colors.white)),
                const SizedBox(width: 12),
                Expanded(child: Text('', style: const TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: widget.navItems.length,
              itemBuilder: (ctx, i) {
                final ni = widget.navItems[i];
                final selected = i == _currentIndex;
                return ListTile(
                  leading: Icon(ni.icon, color: selected ? Colors.orange : Colors.blue.shade800),
                  title: Text(ni.label, style: TextStyle(color: selected ? Colors.orange : Colors.black87, fontWeight: selected ? FontWeight.w700 : FontWeight.w600)),
                  selected: selected,
                  selectedTileColor: Colors.blue.withOpacity(0.05),
                  onTap: () => _selectIndex(i),
                );
              },
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.copy),
              label: const Text('Copiar enlaces'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade900),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// Modelo público para items de navegación
class NavItem {
  final String label;
  final IconData icon;
  final Widget page;
  NavItem({required this.label, required this.icon, required this.page});
}
