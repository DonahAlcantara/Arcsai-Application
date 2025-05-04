<<<<<<< HEAD
// ignore_for_file: deprecated_member_use, use_key_in_widget_constructors, unnecessary_to_list_in_spreads

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';

// Widget to display notifications from Firestore
class NotificationPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // App bar with title and settings button
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
            // Navigate to settings page
            onPressed: () {
              Navigator.pushNamed(context, '/settings');
            },
          ),
        ],
      ),
      // StreamBuilder to fetch and display notifications in real-time
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('notifications')
            .orderBy('timestamp', descending: true) // Sort by latest first
            .snapshots(),
        builder: (context, snapshot) {
          // Handle errors
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          // Show loading indicator while fetching data
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }

          var notifications = snapshot.data!.docs;

          // Display message if no notifications exist
          if (notifications.isEmpty) {
            return Center(
              child: Text(
                "No notifications yet",
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            );
          }

          // Filter notifications for today
          var todayNotifications = notifications.where((notification) {
            var timestamp = (notification['timestamp'] as Timestamp).toDate();
            return isToday(timestamp);
          }).toList();

          // Filter notifications for yesterday
          var yesterdayNotifications = notifications.where((notification) {
            var timestamp = (notification['timestamp'] as Timestamp).toDate();
            return isYesterday(timestamp);
          }).toList();

          // Build list view with sections for today and yesterday
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

  // Check if a date is today
  bool isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  // Check if a date is yesterday
  bool isYesterday(DateTime date) {
    final yesterday = DateTime.now().subtract(Duration(days: 1));
    return date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day;
  }

  // Build a section for notifications (e.g., Today, Yesterday)
  Widget _buildNotificationSection(BuildContext context, String title,
      List<DocumentSnapshot> notifications) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section title
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
          SizedBox(height: 8),
          // List of notification cards
          ...notifications
              .map((notification) =>
                  _buildNotificationCard(context, notification))
              .toList(),
        ],
      ),
    );
  }

  // Build a dismissible notification card
  Widget _buildNotificationCard(
      BuildContext context, DocumentSnapshot notification) {
    var data = notification.data() as Map<String, dynamic>;
    var timestamp = (data['timestamp'] as Timestamp).toDate();
    String formattedTime = _formatTimestamp(timestamp);

    return Dismissible(
      key: Key(notification.id),
      // Delete notification from Firestore on swipe
      onDismissed: (direction) {
        FirebaseFirestore.instance
            .collection('notifications')
            .doc(notification.id)
            .delete();
        // Show confirmation snackbar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Notification deleted'),
            backgroundColor: Theme.of(context).colorScheme.secondary,
          ),
        );
      },
      // Red background with delete icon for swipe left
      background: Container(
        color: Colors.redAccent,
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: Icon(Icons.delete, color: Colors.white),
      ),
      // Red background with delete icon for swipe right
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
            // Notification type indicator dot
            Container(
              width: 10,
              height: 10,
              margin: EdgeInsets.only(top: 5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _getNotificationColor(data['type']),
              ),
            ),
            SizedBox(width: 16),
            // Notification details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Notification title
                  Text(
                    data['title'] ?? "No Title",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  SizedBox(height: 8),
                  // Notification description
                  Text(
                    data['description'] ?? "No Description",
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                  ),
                  SizedBox(height: 8),
                  // Formatted timestamp
                  Text(
                    formattedTime,
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
            // Notification type icon
            Icon(
              _getNotificationIcon(data['type']),
              color: _getNotificationColor(data['type']),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  // Format timestamp for display
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays == 0) {
      return DateFormat('h:mm a').format(timestamp); // e.g., 2:30 PM
    } else if (difference.inDays == 1) {
      return 'Yesterday, ${DateFormat('h:mm a').format(timestamp)}';
    } else {
      return '${difference.inDays} days ago';
    }
  }

  // Get icon based on notification type
  IconData _getNotificationIcon(String? type) {
    switch (type) {
      case 'Battery':
        return Icons.battery_alert;
      case 'Schedule':
        return Icons.schedule;
      case 'Cleaning Started':
        return Icons.play_arrow;
      case 'Cleaning Complete':
        return Icons.check_circle;
      case 'Maintenance':
        return Icons.warning;
      default:
        return Icons.notifications;
    }
  }

  // Get color based on notification type
  Color _getNotificationColor(String? type) {
    switch (type) {
      case 'Battery':
        return Colors.redAccent;
      case 'Schedule':
        return Colors.blueAccent;
      case 'Cleaning Started':
        return Colors.orangeAccent;
      case 'Cleaning Complete':
        return Colors.greenAccent;
      case 'Maintenance':
        return Colors.yellowAccent;
      default:
        return Colors.blueAccent;
    }
  }

  // Add a notification to Firestore
  Future<void> addNotification({
    required String title,
    required String description,
    required String type,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('notifications').add({
        'title': title,
        'description': description,
        'type': type,
        'timestamp': Timestamp.now(),
      });
      print('Notification added: $title - $description');
    } catch (e) {
      print('Error adding notification: $e');
    }
  }

  // Trigger notification for a scheduled cleaning
  void setSchedule(DateTime scheduledTime) async {
    String formattedTime = DateFormat('h:mm a').format(scheduledTime);
    await addNotification(
      title: "Schedule Reminder",
      description: "Your vacuum is scheduled to start at $formattedTime",
      type: "Schedule",
    );
  }

  // Trigger notification for cleaning start
  void startCleaning(DateTime startTime, String room) async {
    String formattedTime = DateFormat('h:mm a').format(startTime);
    await addNotification(
      title: "Cleaning Started",
      description: "Your vacuum started cleaning the $room at $formattedTime",
      type: "Cleaning Started",
    );
  }

  // Trigger notification for cleaning completion
  void stopCleaning(DateTime stopTime) async {
    String formattedTime = DateFormat('h:mm a').format(stopTime);
    await addNotification(
      title: "Cleaning Complete",
      description: "Your vacuum finished cleaning at $formattedTime",
      type: "Cleaning Complete",
    );
  }

  // Trigger notification for low battery
  void lowBattery(int percentage) async {
    await addNotification(
      title: "Battery Low",
      description: "Your vacuum is running low on battery ($percentage%)",
      type: "Battery",
    );
  }

  // Trigger notification for maintenance needs
  void maintenanceRequired(String component) async {
    await addNotification(
      title: "Maintenance Required",
      description: "Your vacuum $component needs to be replaced soon",
      type: "Maintenance",
    );
  }
}

// Widget to set cleaning schedules
class SchedulePage extends StatelessWidget {
  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _roomController = TextEditingController();

  // Set a schedule and trigger a series of test notifications
  Future<void> _setSchedule(
      BuildContext context, DateTime scheduledTime, String room) async {
    try {
      // Trigger schedule reminder notification
      NotificationPage().setSchedule(scheduledTime);

      // Simulate cleaning started notification after 2 seconds
      Timer(Duration(seconds: 2), () {
        print('Triggering Cleaning Started');
        NotificationPage().startCleaning(DateTime.now(), room);
      });

      // Simulate cleaning stopped notification after 4 seconds
      Timer(Duration(seconds: 4), () {
        print('Triggering Cleaning Stopped');
        NotificationPage().stopCleaning(DateTime.now());
      });

      // Simulate low battery and maintenance notifications after 6 seconds
      Timer(Duration(seconds: 6), () {
        print('Triggering Low Battery and Maintenance');
        NotificationPage().lowBattery(15);
        NotificationPage().maintenanceRequired("filter");
      });

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Schedule set successfully")),
      );
    } catch (e) {
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error setting schedule: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // App bar with title
      appBar: AppBar(title: Text("Set Schedule")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Time input field with time picker
            TextField(
              controller: _timeController,
              decoration:
                  InputDecoration(labelText: "Enter time (e.g., 10:00 AM)"),
              readOnly: true,
              onTap: () async {
                // Show time picker dialog
                TimeOfDay? pickedTime = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.now(),
                );
                if (pickedTime != null) {
                  final now = DateTime.now();
                  final scheduledTime = DateTime(
                    now.year,
                    now.month,
                    now.day,
                    pickedTime.hour,
                    pickedTime.minute,
                  );
                  // Update time input field
                  _timeController.text =
                      DateFormat('h:mm a').format(scheduledTime);
                }
              },
            ),
            SizedBox(height: 16),
            // Room input field
            TextField(
              controller: _roomController,
              decoration:
                  InputDecoration(labelText: "Enter room (e.g., Living Room)"),
            ),
            SizedBox(height: 16),
            // Button to set schedule
            ElevatedButton(
              onPressed: () {
                // Validate inputs
                if (_timeController.text.isEmpty ||
                    _roomController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text("Please select a time and enter a room")),
                  );
                  return;
                }
                // Parse selected time
                final scheduledTime =
                    DateFormat('h:mm a').parse(_timeController.text);
                // Set schedule and trigger notifications
                _setSchedule(context, scheduledTime, _roomController.text);
              },
              child: Text("Set Schedule"),
            ),
          ],
        ),
      ),
    );
  }
}
=======
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
>>>>>>> 0636a1a300621acb322bf2346864d4e26f5bbfca
