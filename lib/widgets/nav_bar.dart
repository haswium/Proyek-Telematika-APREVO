import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Satu tab di menu bawah.
class NavItem {
  const NavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Menu bawah APREVO: ungu tua menyatu dengan latar, dengan pil kuning di
/// tab yang aktif (lihat `navigationBarTheme` di app_theme.dart). TalkBack membacakannya sebagai "Tab, 1 dari 3" otomatis.
class AprevoNavBar extends StatelessWidget {
  const AprevoNavBar({
    super.key,
    required this.index,
    required this.onChanged,
    required this.items,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final List<NavItem> items;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.ink,
        border: Border(top: BorderSide(color: AppColors.violet, width: 2)),
      ),
      // Warna, huruf, dan pil kuning diatur di navigationBarTheme (app_theme).
      child: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: onChanged,
        destinations: [
          for (final item in items)
            NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon),
              label: item.label,
            ),
        ],
      ),
    );
  }
}
