from pathlib import Path

manifest = Path('android/app/src/main/AndroidManifest.xml')
if not manifest.exists():
    raise SystemExit('AndroidManifest.xml not found. Run flutter create first.')

text = manifest.read_text(encoding='utf-8')
perms = '''
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
    <uses-permission android:name="android.permission.VIBRATE" />
'''
if 'android.permission.POST_NOTIFICATIONS' not in text:
    text = text.replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android">', '<manifest xmlns:android="http://schemas.android.com/apk/res/android">' + perms)

receivers = '''
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON" />
            </intent-filter>
        </receiver>
'''
if 'ScheduledNotificationReceiver' not in text:
    text = text.replace('</application>', receivers + '    </application>')

text = text.replace('android:label="orbitplan"', 'android:label="OrbitPlan"')
manifest.write_text(text, encoding='utf-8')

# Make minSdk compatible with notifications plugins and older Android devices.
build_gradle = Path('android/app/build.gradle')
if build_gradle.exists():
    bg = build_gradle.read_text(encoding='utf-8')
    bg = bg.replace('minSdk = flutter.minSdkVersion', 'minSdk = 23')
    bg = bg.replace('minSdkVersion flutter.minSdkVersion', 'minSdkVersion 23')
    build_gradle.write_text(bg, encoding='utf-8')
