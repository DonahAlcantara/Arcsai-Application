// ignore_for_file: deprecated_member_use, use_key_in_widget_constructors, unnecessary_to_list_in_spreads

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'settings.dart';

class NotificationPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        title: Text(
          'Notifications',
          style: Theme.of(context).appBarTheme.titleTextStyle,
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.settings,
              color: Theme.of(context).appBarTheme.iconTheme?.color,
            ),
            onPressed: () {
              Navigator.pushNamed(context, '/settings');
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('notifications')
            .orderBy('timestamp', descending: true) // Latest first
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }

          var notifications = snapshot.data!.docs;

          if (notifications.isEmpty) {
            return Center(
              child: Text(
                "No notifications yet",
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            );
          }

          var todayNotifications = notifications.where((notification) {
            var timestamp = (notification['timestamp'] as Timestamp).toDate();
            return isToday(timestamp);
          }).toList();

          var yesterdayNotifications = notifications.where((notification) {
            var timestamp = (notification['timestamp'] as Timestamp).toDate();
            return isYesterday(timestamp);
          }).toList();

          return ListView(
            children: [
              if (todayNotifications.isNotEmpty)
                _buildNotificationSection(context, "Today", todayNotifications),
              if (yesterdayNotifications.isNotEmpty)
                _buildNotificationSection(
                    context, "Yesterday", yesterdayNotifications),
            ],
          );
        },
      ),
    );
  }

  bool isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  bool isYesterday(DateTime date) {
    final yesterday = DateTime.now().subtract(Duration(days: 1));
    return date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day;
  }

  Widget _buildNotificationSection(BuildContext context, String title,
      List<DocumentSnapshot> notifications) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
          SizedBox(height: 8),
          ...notifications
              .map((notification) =>
                  _buildNotificationCard(context, notification))
              .toList(),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(
      BuildContext context, DocumentSnapshot notification) {
    var data = notification.data() as Map<String, dynamic>;
    var timestamp = (data['timestamp'] as Timestamp).toDate();
    return Dismissible(
      key: Key(notification.id),
      onDismissed: (direction) {
        FirebaseFirestore.instance
            .collection('notifications')
            .doc(notification.id)
            .delete();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Notification deleted'),
            backgroundColor: Theme.of(context).colorScheme.secondary,
          ),
        );
      },
      background: Container(
        color: Colors.redAccent,
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: Icon(Icons.delete, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Colors.redAccent,
        alignment: Alignment.centerRight,
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: Icon(Icons.delete, color: Colors.white),
      ),
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 8),
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 8,
              spreadRadius: 2,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _getNotificationIcon(data['type']),
              color: _getNotificationColor(data['type']),
              size: 40,
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data['title'] ?? "No Title",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    data['description'] ?? "No Description",
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    timestamp.toString(),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.color
                          ?.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getNotificationIcon(String? type) {
    switch (type) {
      case 'Battery':
        return Icons.battery_full;
      case 'Schedule':
        return Icons.schedule;
      case 'Vacuum Process':
        return Icons.cleaning_services;
      default:
        return Icons.notifications;
    }
  }

  Color _getNotificationColor(String? type) {
    switch (type) {
      case 'Battery':
        return Colors.greenAccent;
      case 'Schedule':
        return Colors.orangeAccent;
      case 'Vacuum Process':
        return Colors.blueAccent;
      default:
        return Colors.blueAccent;
    }
  }
}
