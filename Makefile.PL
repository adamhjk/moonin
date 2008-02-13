use inc::Module::Install;

name 'Moonin-Web';
all_from 'lib/Moonin/Web.pm';

requires 'Catalyst' => '5.7011';
requires 'Catalyst::Plugin::ConfigLoader';
requires 'Catalyst::Plugin::Static::Simple';
requires 'Catalyst::Action::RenderView';
requires 'Catalyst::Log::Log4perl';
requires 'Moose';
requires 'Exception::Class';
requires 'Time::HiRes';
requires 'Digest::MD5';
requires 'Data::Dump';
requires 'Catalyst::View::TT';
requires 'Cache::FileCache';
requires 'Schedule::Cron';
requires 'Catalyst::Model::Adaptor';
requires 'File::Basename';

requires 'YAML'; # This should reflect the config file format you've chosen
                 # See Catalyst::Plugin::ConfigLoader for supported formats
catalyst;

install_script glob('script/*.pl');
auto_install;
WriteAll;
