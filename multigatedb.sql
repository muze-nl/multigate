-- MySQL dump 8.21
--
-- Host: localhost    Database: multigate
---------------------------------------------------------
-- Server version	3.23.49-log

--
-- Table structure for table 'address'
--

CREATE TABLE address (
  username varchar(32) NOT NULL default '',
  protocol varchar(32) NOT NULL default '',
  address varchar(255) NOT NULL default '',
  main_address enum('true','false') NOT NULL default 'false',
  KEY address (address),
  KEY userprot (username,protocol),
  KEY user (username)
) TYPE=MyISAM;

--
-- Table structure for table 'alias'
--

CREATE TABLE alias (
  alias varchar(32) NOT NULL default '',
  username varchar(32) NOT NULL default '',
  PRIMARY KEY  (alias)
) TYPE=MyISAM;

--
-- Table structure for table 'box'
--

CREATE TABLE box (
  boxname varchar(32) NOT NULL default '',
  username varchar(32) NOT NULL default '',
  contents int(11) NOT NULL default '0',
  UNIQUE KEY boxuser (boxname,username)
) TYPE=MyISAM;

--
-- Table structure for table 'herd'
--

CREATE TABLE herd (
  herdname varchar(32) NOT NULL default '',
  username varchar(32) NOT NULL default '',
  shepherd enum('no','yes') default 'no',
  protocol varchar(32) default NULL,
  UNIQUE KEY herduser (herdname,username),
  KEY herdname (herdname)
) TYPE=MyISAM;

--
-- Table structure for table 'prefprot'
--

CREATE TABLE prefprot (
  username varchar(32) NOT NULL default '',
  protocol varchar(32) NOT NULL default '',
  PRIMARY KEY  (username)
) TYPE=MyISAM;

--
-- Table structure for table 'protocol'
--

CREATE TABLE protocol (
  protocol varchar(32) NOT NULL default '',
  level int(10) unsigned NOT NULL default '0',
  maxmsgsize int(10) unsigned NOT NULL default '0',
  PRIMARY KEY  (protocol)
) TYPE=MyISAM;

--
-- Table structure for table 'user'
--

CREATE TABLE user (
  username varchar(32) NOT NULL default '',
  irl varchar(64) NOT NULL default '',
  level int(10) unsigned NOT NULL default '0',
  password varchar(32) NOT NULL default '',
  birthday date default NULL,
  birthtime time default NULL,
  PRIMARY KEY  (username)
) TYPE=MyISAM;

