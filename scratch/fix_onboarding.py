import re

path = 'lib/screens/onboarding_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

# Fix the end of _introPage
text = text.replace("""            ),
          ],
        ],
      ),
    );
  }""", """            ),
          ],
        ],
      ),
    ),
    ),
    );
  }""")

# Fix _timetableUploadPage start
text = text.replace("""    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [""", """    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [""")

# Fix _timetableUploadPage end
text = text.replace("""          const SizedBox(height: 16),
          Text('You can also add classes manually later',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12)),
        ],
      ),
    );
  }""", """          const SizedBox(height: 16),
          Text('You can also add classes manually later',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12)),
        ],
      ),
    ),
    ),
    );
  }""")

# Fix _locationSetupPage start
text = text.replace("""  Widget _locationSetupPage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [""", """  Widget _locationSetupPage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [""")

# Fix _locationSetupPage end
text = text.replace("""          Text('${_zones.length} zone${_zones.length != 1 ? 's' : ''} selected',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
        ],
      ),
    );
  }""", """          Text('${_zones.length} zone${_zones.length != 1 ? 's' : ''} selected',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
        ],
      ),
    ),
    ),
    );
  }""")

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)

print("Done")
